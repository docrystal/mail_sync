require './mail_sync'
require 'openssl'

class MailSyncApp < Sinatra::Base
  def self.secret
    @secret ||= ENV['APPLICATION_SECRET']
  end

  get '/' do
    'Info https://github.com/docrystal/mail_sync'
  end

  post '/payload' do
    request.body.rewind
    payload_body = request.body.read
    verify_signature(payload_body)

    sync = MailSync.new
    sync.sync_info
    sync.sync_teams
    sync.sync_members

    'Sync'
  end

  private

  def verify_signature(payload_body)
    signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), self.class.secret, payload_body)
    return halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
  end
end
