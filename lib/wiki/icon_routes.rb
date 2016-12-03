
get '/favicon.png' do
  content_type 'image/png'
  headers 'Cache-Control' => "max-age=3600"
  cross_origin
  Favicon.get_or_create(File.join farm_status, 'favicon.png')
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
  redirect "/#{identity['root']}.html"
end
