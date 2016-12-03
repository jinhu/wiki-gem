require 'sinatra'
require 'bundler'
require 'pathname'
Bundler.require

$LOAD_PATH.unshift(File.dirname(__FILE__))
SINATRA_ROOT = File.expand_path(File.dirname(__FILE__))
APP_ROOT = File.expand_path(File.join(SINATRA_ROOT, "..", ".."))

Encoding.default_external = Encoding::UTF_8

require 'server_helpers'
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
  helpers ServerHelpers


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
    pages = @@store.annotated_pages farm_page.directory
    candidates = pages.select do |page|
      datasets = page[:story].select do |key, item|
        item['type']=='paragraph' && item['text'] && item['text'].index(search)
      end
      datasets.length > 0
    end
    halt 404 unless candidates.length > 0
    content_type 'application/json'
    JSON.pretty_generate(candidates.first)
  end

  get %r{/([a-z0-9-]+)\.html} do |name|
    halt 404 unless farm_page.exists?(name)
    haml :page, :locals => {:page => farm_page.get(name), :page_name => name}
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
      page = farm_page.get(name)
    end

    case action['type']
      when 'move'
        page[:story] = action['order'].collect { |id| page['story'].detect { |item| item['id'] == id } || raise('Ignoring move. Try reload.') }
      when 'add'
        page[:story][action['id']] = action['item']
      when 'remove'
        page[:story].except! action['id']
      when 'edit'
        page[:story][action['id']]=action['item']
      when 'create', 'fork'
        page[:story] ||= {}
      else
        puts "unfamiliar action: #{action.inspect}"
        status 501
        return "unfamiliar action"
    end
    (page[:journal] ||= []) << action
    farm_page.put name, page
    "ok"
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

  get %r{/remote/([a-zA-Z0-9:\.-]+)/favicon.png} do |site|
    content_type 'image/png'
    host = site.split(':').first
    if serve_resources_locally?(host)
      Favicon.get_or_create(File.join farm_status(host), 'favicon.png')
    else
      RestClient.get "#{site}/favicon.png"
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

end
