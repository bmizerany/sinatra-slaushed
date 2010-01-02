require 'sha1'
require 'sinatra/base'

module Sinatra

  module Slaushed

    class UserExists < StandardError ; end
    class NeedsAuth < StandardError  ; end


    module Helpers

      def create_user(login, pass)
        hash = uhash(login, pass)
        if redis.setnx k(:auth, login), hash
          true
        else
          raise UserExists
        end
      end

      def authorize
        stoken = session[:stoken]
        @login = redis.get(k(:session, stoken))
        logged_in?
      end

      def login!(login, pass)
          login login, pass
          set_cookie_token
      end

      def login(login, pass)
        found = redis.get(k(:auth, login))

        return false if found.nil?

        if found == uhash(login, pass)
          @login = login
          true
        else
          false
        end
      end

      def logout!
        session.delete :stoken
        redis.delete k(:session, @login)
        @login = nil
      end

      def set_cookie_token
        raise NeedsAuth if !logged_in?
        hash = uhash(Time.now.to_i, @login)
        redis.set k(:session, hash), @login
        session[:stoken] = hash
      end

      def logged_in?
        !!@login
      end

      def uhash(login, pass)
        sha(options.passhash % [login, pass])
      end

      def sha(s) ; Digest::SHA1.hexdigest(s.to_s) ; end
      def k(*a)  ; "slaushed:#{a.join(":")}"      ; end
      def redis  ; options.redis                  ; end

    end

    module WithWeb

      def self.registered(app)
        app.register Sinatra::Slaushed

        app.post "/signup" do
          create_user params[:l], params[:p]
          login!      params[:l], params[:p]

          pass { redirect "/" }
        end

        app.get "/login" do
          pass { erb :login, :views => File.dirname(__FILE__) }
        end

        app.post "/login" do
          login! params[:l], params[:p]
          pass { logged_in? ? redirect("/") : redirect("/login") }
        end

        app.get "/logout" do
          logout!
          pass { redirect "/" }
        end
      end

    end

    private

      def self.registered(app)
        app.set :salt, Proc.new {
          ENV["SLAUSHED_SALT"] || fail("set the SLAUSHED_SALT env var!")
        }

        app.set :passhash, Proc.new { "--{#{salt}-%s-%s}--" }

        app.enable :sessions

        app.helpers Slaushed::Helpers
      end

  end

  register Slaushed
end
