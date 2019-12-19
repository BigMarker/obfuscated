require 'digest/sha1'
require 'active_record'

module Obfuscated
  mattr_accessor :obfuscated_salt

  def self.append_features(base)
    super
    base.extend(ClassMethods)
    base.extend(Finder) 
  end
  
  def self.supported?
    @@mysql_support ||= ActiveRecord::Base.connection.class.to_s.downcase.include?('mysql') ? true : false
  end
  
  module Finder
    def find(*primary_key)
      # Sale.find( '7e2d2c4da1b0' )
      if primary_key.is_a?(String) && primary_key.length == 12
        find_by_obfuscated_id(primary_key)

      # Sale.includes(:store).find( '7e2d2c4da1b0' )
      elsif primary_key.is_a?(Array) && primary_key.length == 1 && primary_key[0].is_a?(String) && primary_key[0].length == 12
        find_by_obfuscated_id(primary_key[0])

      # Other queries
      else
        super
      end
    end
  end

  module ClassMethods
    def has_obfuscated_id( options={} )
      class_eval do

        include Obfuscated::InstanceMethods

        after_commit :set_cached_obfuscated_id, on: :create
        
        def self.find_by_obfuscated_id( hash, options={} )
          if column_names.include?('cached_obfuscated_id')
            c = find_by_cached_obfuscated_id(hash)
            if c
              c
            else
              c = find_by_obfuscated_id_helper(hash, options, true)
              if c
                c.update_column('cached_obfuscated_id', c.obfuscated_id)
                c
              end
            end
          else
            find_by_obfuscated_id_helper(hash, options)
          end
        end
        
        # Uses a 12 character string to find the appropriate record
        def self.find_by_obfuscated_id_helper(hash, options={}, search_null_cache_only=false)
          # Don't bother if there's no hash provided.
          return nil if hash.blank?
          
          # If Obfuscated isn't supported, use ActiveRecord's default finder
          return find_by_id(hash, options) unless Obfuscated::supported?
          
          # Update the conditions to use the hash calculation
          options.update(:conditions => ["SUBSTRING(SHA1(CONCAT('---',#{self.table_name}.id,'-WICKED-#{self.table_name}-#{Obfuscated::obfuscated_salt}')),1,12) = ?", hash])
          
          # Find it!
          if search_null_cache_only && column_names.include?('cached_obfuscated_id')
            where('cached_obfuscated_id is null').first(options) or raise ActiveRecord::RecordNotFound, "Couldn't find #{self.name} with Hashed ID=#{hash}"
          else
            first(options) or raise ActiveRecord::RecordNotFound, "Couldn't find #{self.name} with Hashed ID=#{hash}"
          end
        end
      end
    end

  end
  
  module InstanceMethods
    # Generate an obfuscated 12 character id incorporating the primary key and the table name.
    def obfuscated_id
      raise 'This record does not have a primary key yet!' if id.blank?
      
      # If Obfuscated isn't supported, just return the normal id
      return id unless Obfuscated::supported?
      
      # Use SHA1 to generate a consistent hash based on the id and the table name
      @obfuscated_id ||= Digest::SHA1.hexdigest(
        "---#{id}-WICKED-#{self.class.table_name}-#{Obfuscated::obfuscated_salt}"
      )[0..11]  
    end

    def set_cached_obfuscated_id
      return unless self.class.column_names.include? "cached_obfuscated_id"
      if self.cached_obfuscated_id.nil? || self.obfuscated_id != self.cached_obfuscated_id
        self.update_column('cached_obfuscated_id', self.obfuscated_id)
      end
    end

    def dup
      # Avoid copying memory-cached obfuscated id to new object
      duped = super
      duped.instance_variable_set(:@obfuscated_id, nil)
      duped.cached_obfuscated_id = nil if self.respond_to? :"cached_obfuscated_id="
      duped
    end
  end

end

ActiveRecord::Base.class_eval { include Obfuscated }
