require 'singleton'
require 'json'
require 'bundler/setup'
Bundler.require
Dotenv.load

Octokit.auto_paginate = true

class MailgunClient
  def initialize
    @ml_members = {}
  end

  def conn
    @conn ||= Faraday.new('https://api.mailgun.net/v3') do |conn|
      conn.basic_auth('api', ENV['MAILGUN_API_KEY'])
      conn.request :url_encoded
      conn.response :json, :content_type => /\bjson$/
      conn.adapter Faraday.default_adapter
    end
  end

  def mailing_lists
    @mailing_lists ||= Hash[*(conn.get('lists').body['items'].map { |ml| [ml['address'], ml] }.flatten)]
  end

  def create_mailing_list(name)
    address = "#{name.downcase}@docrystal.org"
    mailing_lists[address] ||= conn.post('lists', address: address, name: name, description: 'via GitHub', access_level: 'everyone').body['list']
  end

  def ml_members(name)
    address = "#{name.downcase}@docrystal.org"
    @ml_members[address] ||= Hash[*(
      conn.get("lists/#{address}/members").body['items'].map { |m| [m['address'], m] }.flatten
    )]
  end

  def add_ml_member(ml_name, name, address)
    ml = "#{ml_name.downcase}@docrystal.org"

    ml_members(ml_name)[address] ||= conn.post("lists/#{ml}/members", address: "#{name} <#{address}>", name: name, subscribed: 'yes', upsert: 'yes').body['member']
  end

  def remove_ml_member(ml, address)
    ml = "#{ml.downcase}@docrystal.org"

    conn.delete("lists/#{ml}/#{address}")
  end
end

class MailSync
  def initialize
    @members = {}
  end

  def github
    @github ||= Octokit::Client.new(access_token: ENV['GITHUB_ACCESS_TOKEN'])
  end

  def mailgun
    @mailgun ||= MailgunClient.new
  end

  def member(id)
    @members[id] ||= github.user(id)
  end

  def teams
    @teams ||= Hash[*(
      github.org_teams('docrystal').map { |team| team.members = team_members(team.id); [team.slug, team] }.flatten
    )]
  end

  def team_members(id)
    github.team_members(id).map { |u| all_members[u.login] }
  end

  def all_members
    @all_members ||= Hash[*(
      github.org_members('docrystal').map { |u| member(u.id) }.select { |u| u.email }.map { |u| [u.login, u] }.flatten
    )]
  end

  def sync_teams
    teams.each_pair do |slug, team|
      mailgun.create_mailing_list(slug)
      team.members.each do |member|
        mailgun.add_ml_member(slug, member.login, member.email)
      end
      member_addresses = team.members.map { |m| m.email }
      ml_members = mailgun.ml_members(slug).keys
      remove_members = ml_members - member_addresses
      remove_members.each do |address|
        mailgun.remove_ml_member(slug, address)
      end
    end
  end

  def sync_info
    all_members.values.each do |member|
      mailgun.add_ml_member('info', member.login, member.email)
    end
    remove_members = mailgun.ml_members('info').keys - all_members.values.map { |m| m.email }
    remove_members.each do |address|
      mailgun.remove_ml_member('info', address)
    end
  end
end

MailSync.instance.sync_info
MailSync.instance.sync_teams
