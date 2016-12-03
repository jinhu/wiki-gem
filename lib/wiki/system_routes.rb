
get '/system/sitemap.json' do
  content_type 'application/json'
  cross_origin
  pages = @@store.annotated_pages farm_page.directory
  sitemap = pages.collect {|p| {"slug" => p['name'], "title" => p['title'], "date" => p['updated_at'].to_i*1000, "synopsis" => synopsis(p)}}
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
  end.reject {|info| info.nil?}
  JSON.pretty_generate factories
end

get '/system/plugins.json' do
  content_type 'application/json'
  cross_origin
  plugins = []
  path = File.join(APP_ROOT, "client/plugins")
  pathname = Pathname.new path
  Dir.glob("#{path}/*/") {|filename| plugins << Pathname.new(filename).relative_path_from(pathname)}
  JSON.pretty_generate plugins
end

get '/system/slugs.json' do
  content_type 'application/json'
  cross_origin
  JSON.pretty_generate(Dir.entries(farm_page.directory).reject{|e|e[0] == '.'})
end
