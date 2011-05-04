require 'digest/md5'
require 'redis'

module Canonicurl
  class Cache
    CANONICAL  = 'C'
    ERROR      = 'E'
    RESOLVING  = 'R'

    TTL = 60 * 60 * 24 * 90 # 90 days ~ 3 months
    ERROR_TTL = 60 * 60 # 1 hour
    KEY_PREFIX = 'curl:'

    attr_accessor :db, :ttl, :error_ttl, :status_ttl
    attr_reader :key_prefix

    def self.url(code_or_url)
      code_or_url && code_or_url.size > 3 ? code_or_url : nil
    end


    def initialize(options={})
      @db         = options[:db] || Redis.connect
      @ttl        = options[:ttl] || TTL
      @error_ttl  = options[:error_ttl] || ERROR_TTL
      @status_ttl = options[:status_ttl] || ERROR_TTL
      @key_prefix = options[:key_prefix] || KEY_PREFIX
    end


    def get(url)
      @db.get key(url)
    end


    def fetch(url, resolver)
      k = key(url)

      # New URL, resolve it
      if @db.setnx(k, RESOLVING) #  lock it if key doesn't exist
        return resolve(url, k, resolver)
      end

      result = @db.get(k)
      if !result.nil? && result.size > 3
        return result # Found cached noncanonical URL mapping
      end

      # CANONICAL, ERROR, RESOLVING, custom status, or nil
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
      begin
        resolved = resolver.call(url).to_s
      rescue Exception => e
        @db.setex(url_key, @error_ttl, ERROR)
        raise e
      end

      if resolved.size > 3
        set url, resolved, url_key
        resolved
      else # resolver can return status code that is less than 3 characters long
        # any internal status code is always marked as ERROR w/ error_ttl
        if [CANONICAL, ERROR, RESOLVING].include?(resolved)
          @db.setex(url_key, @error_ttl, ERROR)
          ERROR
        else # status / acknowleged error (e.g. 500) is marked w/ given status code and status_ttl
          @db.setex(url_key, @status_ttl, resolved)
          resolved
        end
      end
    end

  end
end
