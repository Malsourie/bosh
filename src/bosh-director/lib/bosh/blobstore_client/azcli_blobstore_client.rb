require 'openssl'
require 'digest/sha1'
require 'base64'
require 'securerandom'
require 'open3'
require 'json'

module Bosh::Blobstore
  class AzcliBlobstoreClient < BaseClient
    # Blobstore client for az storage account, using azcli Go version
    # @param [Hash] options azconnection options
    # @option options [Symbol] account_name
    #   key that is applied before the object is sent to az
    # @option options [Symbol, optional] account_key
    # @option options [Symbol] azcli_path
    #   path to azcli binary
    # @option options [Symbol, optional] azcli_config_path
    #   path to store configuration files
    def initialize(options)
      super(options)

      @azcli_path = @options.fetch(:azcli_path)

      # Uncomment below codes if '-v' is implemented in azcli
      # unless Kernel.system(@azcli_path.to_s, '--v', out: '/dev/null', err: '/dev/null')
      #   raise BlobstoreError, 'Cannot find azcli executable. Please specify azcli_path parameter'
      # end

      @azcli_options = {
        "account-name": @options[:account_name],
        "container-name": @options[:container_name],
        "account-key": @options[:account_key]
      }

      @azcli_options.reject! { |_k, v| v.nil? }

      @config_file = write_config_file(@azcli_options, @options.fetch(:azcli_config_path, nil))
    end

    def redacted_credential_properties_list
      %w[account_key]
    end

    def encryption_headers; end

    def encryption?
      false
    end

    protected

    # @param [File] file file to store in az storage account
    def create_file(object_id, file)
      object_id ||= generate_object_id
      # in Ruby 1.8 File doesn't respond to :path
      path = file.respond_to?(:path) ? file.path : file

      store_in_az(path, full_oid_path(object_id))

      object_id
    end

    # @param [String] object_id object id to retrieve
    # @param [File] file file to store the retrieved object in
    def get_file(object_id, file)
      begin
        out, err, status = Open3.capture3(@azcli_path.to_s, '-c', @config_file.to_s, 'get', object_id.to_s, file.path.to_s)
      rescue Exception => e
        raise BlobstoreError, e.inspect
      end
      return if status.success?

      raise NotFound, "Blobstore object '#{object_id}' not found" if err =~ /NoSuchKey/

      raise BlobstoreError, "Failed to download az storage account object, code #{status.exitstatus}, output: '#{out}', error: '#{err}'"
    end

    # @param [String] object_id object id to delete
    def delete_object(object_id)
      begin
        out, err, status = Open3.capture3(@azcli_path.to_s, '-c', @config_file.to_s, 'delete', object_id.to_s)
      rescue Exception => e
        raise BlobstoreError, e.inspect
      end
      raise BlobstoreError, "Failed to delete az storage account object, code #{status.exitstatus}, output: '#{out}', error: '#{err}'" unless status.success?
    end

    def object_exists?(object_id)
      begin
        out, err, status = Open3.capture3(@azcli_path.to_s, '-c', @config_file.to_s, 'exists', object_id.to_s)
        return true if status.exitstatus.zero?
        return false if status.exitstatus == 3
      rescue Exception => e
        raise BlobstoreError, e.inspect
      end
      raise BlobstoreError, "Failed to check existence of az storage account object, code #{status.exitstatus}, output: '#{out}', error: '#{err}'" unless status.success?
    end

    def sign_url(object_id, verb, duration)
      begin
        out, err, status = Open3.capture3(
          @azcli_path.to_s,
          '-c',
          @config_file.to_s,
          'sign',
          object_id.to_s,
          verb.to_s,
          duration.to_s,
        )
      rescue Exception => e
        raise BlobstoreError, e.inspect
      end

      return out if status.success?

      raise BlobstoreError, "Failed to sign url, code #{status.exitstatus}, output: '#{out}', error: '#{err}'"
    end

    def required_credential_properties_list
      %w[account_key]
    end

    # @param [String] path path to file which will be stored in az storage account
    # @param [String] oid object id
    # @return [void]
    def store_in_az(path, oid)
      begin
        out, err, status = Open3.capture3(@azcli_path.to_s, '-c', @config_file.to_s, 'put', path.to_s, oid.to_s)
      rescue Exception => e
        raise BlobstoreError, e.inspect
      end
      raise BlobstoreError, "Failed to create az storage account object, code #{status.exitstatus}, output: '#{out}', error: '#{err}'" unless status.success?
    end

    def full_oid_path(object_id)
      @options[:folder] ? @options[:folder] + '/' + object_id : object_id
    end
  end
end
