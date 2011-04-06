require 'digest/md5'
require 'redis'
require 'em-http'

module Canonicurl  
  class Cache
    CANONICAL  = 'C'
    ERROR      = 'E'
    LOCKED     = 'L'
    RESOLVING  = 'R'

    TTL = 60 * 60 * 24 * 90 # 90 days ~ 3 months
    REDIRECTS = 5
    CONNECTION_TIMEOUT = 5
    KEY_PREFIX = 'curl:'

    attr_accessor :db, :ttl, :timeout, :redirects
    attr_reader :key_prefix

    def self.url(code_or_url)
      code_or_url && code_or_url.size > 1 ? code_or_url : nil
    end


    def initialize(options={})
      @db         = options[:db] || Redis.connect
      @ttl        = options[:ttl] || TTL
      @timeout    = options[:timeout] || CONNECTION_TIMEOUT
      @redirects  = options[:redirects] || REDIRECTS
      @key_prefix = options[:key_prefix] || KEY_PREFIX
    end


    def get(url)
      @db.get key(url)
    end


    def fetch(url, callbacks={})
      k = key(url)
      @db.setnx(k, LOCKED) #  lock it if key doesn't exist

      result = @db.get(k)
      if !result.nil? && result.size > 1
        return result

      end

      case result
      when CANONICAL
        yield url
      when LOCKED
        resolve(url, k, callbacks)
        RESOLVING
      else
        result
      end
    end


    def set(url, canonical_url, url_key=nil)
      url_key = url_key || key(url)
      if url == canonical_url
        @db.setex(url_key, @ttl, CANONICAL)
      else
        @db.setex(url_key, @ttl, canonical_url)
        @db.setex(key(canonical_url), @ttl, CANONICAL) # preemptively set the canonical_url
      end
    end


    def key(url)
      "#{@key_prefix}#{Digest::MD5.hexdigest(url)}"
    end


    private

      def resolve(url, url_key, callbacks)
        em_already_running = true
        @db.set(url_key, RESOLVING)
        em do |running|
          em_already_running = running
          http = EM::HttpRequest.new(url,
                  :connection_timeout => @timeout,
                  :inactivity_timeout => @timeout * 2).get(:redirects => @redirects)
          http.callback {
            status = http.response_header.status.to_i
            case status
            when 200...300
              canonical_url = http.last_effective_url.to_s
              set url, canonical_url, url_key
              callbacks[:resolved].call(canonical_url, http) if callbacks[:resolved]
            else
              @db.set url_key, (status / 100).to_s
              callbacks[:failed].call(http) if callbacks[:failed]
            end
            EM.stop unless em_already_running
          }    
          http.errback  {
            @db.set(url_key, ERROR) 
            callbacks[:error].call(http) if callbacks[:error]
            EM.stop unless em_already_running
          }
        end
      rescue Exception => e
        @db.set(url_key, ERROR)
        callbacks[:exception].call(e) if callbacks[:exception]
        EM.stop unless em_already_running
      end


      def em
        if EM.reactor_running? 
          yield true
        else
          EM.run do
            yield false
          end
        end
      end
  end
end
