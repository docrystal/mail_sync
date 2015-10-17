require 'openssl'
require './mail_sync'

class MailSyncApp < Sinatra::Base
  HMAC_DIGEST = OpenSSL::Digest::Digest.new('sha1')

  def self.secret
    @secret ||= ENV['APPLICATION_SECRET']
  end

  before do
    request.body.rewind
    @request_body = request.body.read

    if request.body.size > 0
      request.body.rewind
      begin
        @params = JSON.parse(request.body.read, symbolize_names: true)
      rescue JSON::JSONError
      end
    end
  end

  get '/' do
    'Info https://github.com/docrystal/mail_sync'
  end

  post '/payload' do
    if request['X-Hub-Signature'] != expected_secret
      halt 403
    end

    if request['X-Github-Event'] == 'ping'
      return 'OK'
    end

    sync = MailSync.new
    sync.sync_info
    sync.sync_teams

    'Sync'
  end

  private

  def expected_secret
    'sha1='+OpenSSL::HMAC.hexdigest(HMAC_DIGEST, self.class.secret, @request_body)
  end
end
