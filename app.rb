require 'fileutils'
require 'json'

require 'sinatra'
require 'sinatra/reloader' if development?
require 'slim'
require 'sass'
require 'sanitize'
require 'redcarpet'
require 'scrypt'

helpers do
  def sanitize(html)
    config = Sanitize::Config::BASIC
    config[:elements] += %w[h1 h2 h3 h4 h5 h6 hgroup]
    Sanitize.clean(html, config)
  end

  def read(path)
    open(path) do |file|
      ext = File.extname(path)
      content = file.read
      return content if ['.txt'].include?(ext)

      content = markdown(content) if ['.md', '.markdown'].include?(ext)
      content = sanitize(content)
      return content
    end
  end

  def user_path(username)
    File.join('files', username[0], username)
  end
end

configure do
  set :slim, :pretty => true
  set :css_style => :expanded
  enable :sessions
end

get '/' do
end

get '/login' do
  slim :login
end

post '/login' do
  halt(406, slim(:login)) unless params['username'] =~ /\A\w{3,15}\z/
  halt(406, slim(:login)) unless params['password'] =~ /\A.{6,}\z/

  user_path = user_path(params['username'])
  halt(406, slim(:login)) unless File.exist?(user_path)

  conf_path = File.join(user_path, '.config.json')
  open(conf_path) do |file|
    json = file.read
    config = JSON.load(json)
    password = SCrypt::Password.new(config['password'])
    halt(403, slim(:login)) unless password == params['password']

    # TODO: Send token to email address?
  end

  session[:username] = params['username'] # FIXME: Remove this
  redirect '/'
end

get '/join' do
  slim :join
end

post '/join' do
  # TODO: Verify email address
  halt(406) unless params['username'] =~ /\A\w{3,15}\z/
  halt(406) unless params['password'] =~ /\A.{6,}\z/
  halt(406) unless params['email'] =~ /@/

  user_path = user_path(params['username'])
  halt(406) if File.exist?(user_path)

  FileUtils.mkdir_p(user_path)

  config = {
    email: params['email'],
    password: SCrypt::Password.create(params['password'])
  }
  json = JSON.pretty_generate(config)
  conf_path = File.join(user_path, '.config.json')
  open(conf_path, 'w') do |file|
    file.write(json)
  end

  session[:username] = params['username']
  redirect '/'
end

get '/edit/*' do |path|
  halt(403) unless session.key?(:username)
  user_path = user_path(session[:username])

  file_path = File.join(user_path, path)
  if File.file?(file_path)
    open(file_path) do |file|
      @content = file.read
    end
  else
    @content = ''
  end
  slim :edit
end

post '/edit/*' do |path|
  halt(403) unless session.key?(:username)
  user_path = user_path(session['username'])

  content = params['content']
  file_path = File.join(user_path, path)
  FileUtils.mkdir_p(File.dirname(file_path))
  open(file_path, 'w') do |file|
    file.write(content)
  end

  redirect "/~#{session['username']}/#{path}"
end

before '/~*.txt' do
  content_type('text/plain')
end

get '/~:username/?*' do |username, path|
  @path = path
  @author = username
  @username = session[:username]

  user_path = user_path(username)
  file_path = File.join(user_path, path)
  halt(404) unless File.exists?(file_path)

  if File.directory?(file_path)
    redirect("#{request.path}/") unless request.path[-1] == '/'
    @files = Dir.entries(file_path).sort.reject { |f| f[0] == '.' }
    indexes = @files.grep(/^index\.(htm|html|md|markdown)$/)
    if indexes.empty?
      view = :list
    else
      file_path = File.join(file_path, indexes.first)
    end
  end

  if File.file?(file_path)
    @content = read(file_path)
    @title = @content.split.first.gsub(/<.*?>/, '')
    view = :page
  end

  slim view
end

get '/styles/*.css' do |style|
  scss :"styles/#{style}"
end
