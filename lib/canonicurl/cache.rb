require 'digest/md5'
require 'redis'

module Canonicurl  
  class Cache
    CANONICAL  = 'C'
    ERROR      = 'E'
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


    def fetch(url, resolver)
      k = key(url)

      # New URL resolve it
      if @db.setnx(k, RESOLVING) #  lock it if key doesn't exist
        return resolve(url, k, resolver)
      end

      result = @db.get(k)
      if !result.nil? && result.size > 1
        return result # Found old noncanonical URL mapping
      end

      # CANONICAL, ERROR or RESOLVING
      result == CANONICAL ? url : result
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

    def resolve(url, url_key, resolver)
      @db.set(url_key, RESOLVING)
      begin
        canonical_url = resolver.call(url).to_s
      rescue Exception => e
        @db.set(url_key, ERROR)
        raise e
      end

      if canonical_url.size > 1
        set url, canonical_url, url_key
        canonical_url
      else
        if canonical_url.size == 1 && ![CANONICAL, ERROR, LOCKED, RESOLVING].include?(canonical_url)
          @db.set(url_key, canonical_url) # save status
          canonical_url
        else
          @db.set(url_key, ERROR) # error
          ERROR
        end
      end
    end

  end
end
