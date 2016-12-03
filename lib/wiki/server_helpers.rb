module ServerHelpers

  def cross_origin
    headers 'Access-Control-Allow-Origin' => "*" if request.env['HTTP_ORIGIN']
  end

  def resolve_links string
    string.
      gsub(/\[\[([^\]]+)\]\]/i) {
                  |name|
                  name.gsub!(/^\[\[(.*)\]\]/, '\1')

                  slug = name.gsub(/\s/, '-')
                  slug = slug.gsub(/[^A-Za-z0-9-]/, '').downcase
                  '<a class="internal" href="/'+slug+'.html" data-page-name="'+slug+'" >'+name+'</a>'
              }.
      gsub(/\[(http.*?) (.*?)\]/i, '<a class="external" href="\1" rel="nofollow">\2</a>')
  end

  def openid_consumer
    @openid_consumer ||= OpenID::Consumer.new(session, OpenID::Store::Filesystem.new("#{farm_status}/tmp/openid"))
  end

  def authenticated?
    session[:authenticated] == true
  end

  def identified?
    GitStore.exists? "#{farm_status}/open_id.identifier"
  end

  def claimed?
    GitStore.exists? "#{farm_status}/open_id.identity"
  end

  def authenticate!
    session[:authenticated] = true
    redirect "/"
  end

  def oops status, message
    haml :oops, :layout => false, :locals => {:status => status, :message => message}
  end

  def serve_resources_locally?(site)
    !!ENV['FARM_DOMAINS'] && ENV['FARM_DOMAINS'].split(',').any?{|domain| site.end_with?(domain)}
  end

  def serve_page(name, site=request.host)
    cross_origin
    halt 404 unless farm_page(site).exists?(name)
    JSON.pretty_generate farm_page(site).get(name)
  end

  def synopsis page
    text = page['synopsis']
    p1 = page['story'] && page['story'][0]
    p2 = page['story'] && page['story'][1]
    text ||= p1 && p1['text'] if p1 && p1['type'] == 'paragraph'
    text ||= p2 && p2['text'] if p2 && p2['type'] == 'paragraph'
    text ||= p1 && p1['text'] || p2 && p2['text'] || page['story'] && "A page with #{page['story'].length} paragraphs." || "A page with no story."
    return text
  end


  def farm_page(site=request.host)
    page = Page.new
    page.directory = File.join data_dir(site), "pages"
    page.default_directory = File.join APP_ROOT, "default-data", "pages"
    page.plugins_directory = File.join APP_ROOT, "node_modules"
    @@store.mkdir page.directory
    page
  end

  def farm_status(site=request.host)
    status = File.join data_dir(site), "status"
    @@store.mkdir status
    status
  end

  def data_dir(site)
    @@store.farm?(self.class.data_root) ? File.join(self.class.data_root, "farm", site) : self.class.data_root
  end

  def identity
    default_path = File.join APP_ROOT, "default-data", "status", "local-identity"
    real_path = File.join farm_status, "local-identity"
    id_data = @@store.get_hash( real_path)[:story]
    id_data ||= @@store.put_hash(real_path, @@store.get_hash(default_path))
  end

end

