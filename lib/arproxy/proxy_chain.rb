module Arproxy
  autoload :ChainTail, "arproxy/chain_tail"

  class ProxyChain
    attr_reader :head, :tail

    def initialize(config)
      @config = config
      setup
    end

    def setup
      @tail = ChainTail.new self
      @head = @config.proxies.reverse.inject(@tail) do |next_proxy, proxy_config|
        cls, options = proxy_config
        proxy = cls.new(*options)
        proxy.proxy_chain = self
        proxy.next_proxy = next_proxy
        proxy
      end
    end
    private :setup

    def reenable!
      disable!
      setup
      enable!
    end

    def enable!
      @config.adapter_class.class_eval do
        if instance_method(:execute).parameters.any? { |kind, name| kind == :key && name == :async }
          # ActiveRecord 7.0.0+ with MySQL
          # ref. https://github.com/rails/rails/blob/v7.0.0/activerecord/lib/active_record/connection_adapters/mysql/database_statements.rb#L43
          def execute_with_arproxy(sql, name=nil, **kwargs)
            ::Arproxy.proxy_chain.connection = self
            ::Arproxy.proxy_chain.head.execute sql, name, **kwargs
          end
        else
          def execute_with_arproxy(sql, name=nil)
            ::Arproxy.proxy_chain.connection = self
            ::Arproxy.proxy_chain.head.execute sql, name
          end
        end
        alias_method :execute_without_arproxy, :execute
        alias_method :execute, :execute_with_arproxy
        ::Arproxy.logger.debug("Arproxy: Enabled")
      end
    end

    def disable!
      @config.adapter_class.class_eval do
        alias_method :execute, :execute_without_arproxy
        ::Arproxy.logger.debug("Arproxy: Disabled")
      end
    end

    def connection
      Thread.current[:arproxy_connection]
    end

    def connection=(val)
      Thread.current[:arproxy_connection] = val
    end

  end
end
