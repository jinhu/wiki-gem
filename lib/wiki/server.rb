require 'sinatra'
require 'bundler'
require 'pathname'
Bundler.require

$LOAD_PATH.unshift(File.dirname(__FILE__))
SINATRA_ROOT = File.expand_path(File.dirname(__FILE__))
APP_ROOT = File.expand_path(File.join(SINATRA_ROOT, "..", ".."))

Encoding.default_external = Encoding::UTF_8

require 'server_helpers'
require 'system_routes'
require 'stores/git'
require 'page'
require 'favicon'

require 'openid'
require 'openid/store/filesystem'

class Controller < Sinatra::Base
  @@store = GitStore.instance(APP_ROOT)

  set :port, 1111
  set :public_folder, File.join(APP_ROOT, "node_modules/wiki-client/client")
  set :views, File.join(SINATRA_ROOT, "views")
  set :haml, :format => :html5
  set :versions, `git log -10 --oneline` || "no git log"

  if ENV.include?('SESSION_STORE')
    use ENV['SESSION_STORE'].split('::').inject(Object) { |mod, const| mod.const_get(const) }
  else
    enable :sessions
  end
  include ServerHelpers
  include SystemRoutes

  class << self # overridden in test
    def data_root
      File.join APP_ROOT, "data"
    end
  end

  get /\/plugins\/(.*?)\/(.*)/ do |plugin, file|
    send_file File.join(APP_ROOT, "node_modules/wiki-plugin-#{plugin}/client", file)
  end

  get %r{/data/([\w -]+)} do |search|
    cross_origin
    candidates = @@store.find(search)
    halt 404 unless candidates.length > 0
    content_type 'application/json'
    JSON.pretty_generate(candidates.first)
  end

  get %r{/([a-z0-9-]+)\.html} do |name|
    halt 404 unless @@store.farm_page(request.host).exists?(name)
    haml :page, :locals => {:page => @@store.farm_page(request.host).get(name), :page_name => name}
  end

  get %r{((/[a-zA-Z0-9:.-]+/[a-z0-9-]+(_rev\d+)?)+)} do
    elements = params[:captures].first.split('/')
    pages = []
    elements.shift
    while (site = elements.shift) && (id = elements.shift)
      if site == 'view'
        pages << {:id => id}
      else
        pages << {:id => id, :site => site}
      end
    end
    haml :view, :locals => {:pages => pages}
  end

  get %r{/([a-z0-9-]+)\.json} do |name|
    content_type 'application/json'
    serve_page name
  end

  def serve_page(name, site=request.host)
    cross_origin
    halt 404 unless @@store.farm_page(site).exists?(name)
    JSON.pretty_generate @@store.farm_page.get(name)
  end


  error 403 do
    'Access forbidden'
  end

  put %r{/page/([a-z0-9-]+)/action} do |name|
    unless authenticated? or (!identified? and !claimed?)
      halt 403
      return
    end

    action = JSON.parse params['action']
    if site = action['fork']
      # this fork is bundled with some other action
      page = JSON.parse RestClient.get("#{site}/#{name}.json")
      (page['journal'] ||= []) << {'type' => 'fork', 'site' => site}
      farm_page.put name, page
      action.delete 'fork'
    elsif action['type'] == 'create'
      return halt 409 if farm_page.exists?(name)
      page = action['item'].clone
    elsif action['type'] == 'fork'
      if action['item']
        page = action['item'].clone
        action.delete 'item'
      else
        page = JSON.parse RestClient.get("#{action['site']}/#{name}.json")
      end
    else
      page = @@store.farm_page(request.host).get(name)
    end

  end

  get %r{/remote/([a-zA-Z0-9:\.-]+)/([a-z0-9-]+)\.json} do |site, name|
    content_type 'application/json'
    host = site.split(':').first
    if serve_resources_locally?(host)
      serve_page(name, host)
    else
      RestClient.get "#{site}/#{name}.json" do |response, request, result, &block|
        case response.code
          when 200
            response
          when 404
            halt 404
          else
            response.return!(request, result, &block)
        end
      end
    end
  end

  not_found do
    oops 404, "Page not found"
  end

  put '/submit' do
    content_type 'application/json'
    bundle = JSON.parse params['bundle']
    spawn = "#{(rand*1000000).to_i}.#{request.host}"
    site = request.port == 80 ? spawn : "#{spawn}:#{request.port}"
    bundle.each do |slug, page|
      farm_page(spawn).put slug, page
    end
    citation = {
        "type" => "reference",
        "id" => rand(36**length).to_s(16),
        "site" => site,
        "slug" => "recent-changes",
        "title" => "Recent Changes",
        "text" => bundle.collect { |slug, page| "<li> [[#{page['title']||slug}]]" }.join("\n")
    }
    action = {
        "type" => "add",
        "id" => citation['id'],
        "date" => Time.new.to_i*1000,
        "item" => citation
    }
    slug = 'recent-submissions'
    page = farm_page.get slug
    (page['story']||=[]) << citation
    (page['journal']||=[]) << action
    farm_page.put slug, page
    JSON.pretty_generate citation
  end

  def identified?
    @@store.identified? request.host
  end

  def claimed?
    @@store.claimed? request.host
  end


  get '/system/sitemap.json' do
    content_type 'application/json'
    cross_origin
    pages = @@store.annotated_pages @@store.farm_page.directory
    sitemap = pages.collect { |p| {"slug" => p['name'], "title" => p['title'], "date" => p['updated_at'].to_i*1000, "synopsis" => synopsis(p)} }
    JSON.pretty_generate sitemap
  end

  get '/system/factories.json' do
    content_type 'application/json'
    cross_origin
    # return "[]"
    factories = Dir.glob(File.join(APP_ROOT, "client/plugins/*/factory.json")).collect do |info|
      begin
        JSON.parse(File.read(info))
      rescue
      end
    end.reject { |info| info.nil? }
    JSON.pretty_generate factories
  end

  get '/system/plugins.json' do
    content_type 'application/json'
    cross_origin
    plugins = []
    path = File.join(APP_ROOT, "client/plugins")
    pathname = Pathname.new path
    Dir.glob("#{path}/*/") { |filename| plugins << Pathname.new(filename).relative_path_from(pathname) }
    JSON.pretty_generate plugins
  end

  get '/system/slugs.json' do
    content_type 'application/json'
    cross_origin
    JSON.pretty_generate(Dir.entries(farm_page.directory).reject { |e| e[0] == '.' })
  end

  post "/logout" do
    session.delete :authenticated
    redirect "/"
  end

  post '/login' do
    begin
      root_url = request.url.match(/(^.*\/{2}[^\/]*)/)[1]
      identifier_file = File.join @@store.farm_status(request.host), "_open_id.identifier"
      identifier = @@store.get_text(identifier_file)
      unless identifier
        identifier = params[:identifier]
      end
      open_id_request = openid_consumer.begin(identifier)

      redirect open_id_request.redirect_url(root_url, root_url + "/login/openid/complete")
    rescue
      oops 400, "Trouble starting OpenID<br>Did you enter a proper endpoint?"
    end
  end

  get '/login/openid/complete' do
    begin
      response = openid_consumer.complete(params, request.url)
      case response.status
        when OpenID::Consumer::FAILURE
          oops 401, "Login failure"
        when OpenID::Consumer::SETUP_NEEDED
          oops 400, "Setup needed"
        when OpenID::Consumer::CANCEL
          oops 400, "Login cancelled"
        when OpenID::Consumer::SUCCESS
          id = params['openid.identity']
          id_file = File.join farm_status, "open_id.identity"
          stored_id = @@store.get_text(id_file)
          if stored_id
            if stored_id == id
              # login successful
              authenticate!
            else
              oops 403, "This is not your wiki"
            end
          else
            @@store.put_text id_file, id
            # claim successful
            authenticate!
          end
        else
          oops 400, "Trouble with OpenID"
      end
    rescue
      oops 400, "Trouble running OpenID<br>Did you enter a proper endpoint?"
    end
  end



  get '/favicon.png' do
    content_type 'image/png'
    headers 'Cache-Control' => "max-age=3600"
    cross_origin
    Favicon.get_or_create(File.join @@store.farm_status, 'favicon.png')
  end

  get '/random.png' do
    unless authenticated? or (!identified? and !claimed?)
      halt 403
      return
    end

    content_type 'image/png'
    path = File.join farm_status, 'favicon.png'
    GitStore.put_blob path, Favicon.create_blob
  end

  get '/' do
    redirect "/#{@@store.identity['root']}.html"
  end

  get %r{/remote/([a-zA-Z0-9:\.-]+)/favicon.png} do |site|
    content_type 'image/png'
    host = site.split(':').first
    if serve_resources_locally?(host)
      Favicon.get_or_create(File.join farm_status(host), 'favicon.png')
    else
      RestClient.get "#{site}/favicon.png"
    end
  end

end
