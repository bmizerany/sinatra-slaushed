require 'contest'
require 'redis'
require 'rack/test'
require 'sinatra/slaushed'

R = Redis.new(:db => 2)

class SinatraSlaushedTest < Test::Unit::TestCase
  include Rack::Test::Methods

  describe "Sinatra::Slaushed" do

    setup do
      R.flushdb
    end

    describe "Helpers" do

      setup do
        @app = Class.new(Sinatra::Base).tap {|app|
          app.register Sinatra::Slaushed

          ## Set the test salt here, use the SLAUSHED_SALT env in prod!
          app.set :salt, "soy-sauce"
          app.set :redis, R

          ## This is a hack to avoid returning a Rack::Session::Cookie on #new
          app.disable :sessions

        }.new

        def @app.env ; @env ||= {} ; end
      end

      test "create_user creates a user" do
        assert @app.create_user "blake", "foo"
      end

      test "invalid login" do
        assert !@app.login("blake", "foo")
        assert !@app.logged_in?
      end

      test "create_user then login" do
        @app.create_user "blake", "foo"
        assert @app.login "blake", "foo"
        assert @app.logged_in?
      end

      test "sets the token in session" do
        @app.create_user "blake", "foo"
        @app.login "blake", "foo"
        @app.set_cookie_token

        assert_not_nil @app.session[:stoken]
      end

    end

    describe "Web" do
      include Rack::Test::Methods

      def app 
        app = Class.new(Sinatra::Base)

        app.register Sinatra::Slaushed::WithWeb

        app.set :salt,  "soy-sauce"
        app.set :redis, R
        app.template(:login) { "LOGIN!" }
        app.get("/foo") { authorize || redirect("/login") ; "foo" }
        app
      end

      test "signup / login / logout" do
        ## Start by signing up
        post "/signup", :l => "blake", :p => "foo"

        assert last_request.env["rack.session"].has_key?(:stoken)

        follow_redirect!

        assert_equal "http://example.org/", last_request.url

        ## Attempt access to resource with authentication
        get "/foo"

        assert       last_response.ok?
        assert_equal "foo", last_response.body

        ## Log out user
        get "/logout"
        follow_redirect!
        assert_equal "http://example.org/", last_request.url

        ## Attempt access to resource without authentication
        get "/foo"
        follow_redirect!

        assert_equal "http://example.org/login", last_request.url
      end

    end

  end

end
