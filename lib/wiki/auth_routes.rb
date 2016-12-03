
post "/logout" do
  session.delete :authenticated
  redirect "/"
end

post '/login' do
  begin
    root_url = request.url.match(/(^.*\/{2}[^\/]*)/)[1]
    identifier_file = File.join farm_status, "open_id.identifier"
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
