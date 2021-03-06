require 'typhoeus'

module GDataPlus
  class Client
    attr_reader :authenticator, :default_gdata_version

    def initialize(authenticator, default_gdata_version = "2.0")
      @authenticator = authenticator
      @default_gdata_version = default_gdata_version
    end

    # FIXME detect infinite redirect
    def submit(request, options = {})
      options = ::GDataPlus::Util.prepare_options(options, [], [:gdata_version, :hydra, :no_redirect])
      hydra = options[:hydra] || Typhoeus::Hydra.hydra

      request.headers.merge!("GData-Version" => options[:gdata_version] || default_gdata_version)
      @authenticator.sign_request(request)

      # add "If-Match: *" header if there is not already a conditional header and
      # the request is not a post (since If-Match headers on POSTs triggers concurreny-errors)
      if !request.headers.keys.any? { |key| key =~ /^If-/ } && !request.method == :post
        request.headers.merge!("If-Match" => "*")
      end

      hydra.queue(request)
      hydra.run
      response = request.response

      # automatically follow redirects since some GData APIs (like Calendar) redirect GET requests
      if request.method.to_sym == :get && !options[:no_redirect] && (300..399).include?(response.code)
        response = submit ::Typhoeus::Request.new(response.headers_hash["Location"], :method => :get), options.merge(:no_redirect => true)
      end

      Util.raise_if_error(response)

      response
    end

    [:delete, :get, :post, :put].each do |method|
      define_method(method) do |*args|
        args[1] ||= {}
        args[1] = args[1].merge(:method => method)
        request = ::Typhoeus::Request.new(*args)
        submit request
      end
    end
  end
end