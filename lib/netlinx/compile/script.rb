require 'optparse'
require 'ostruct'
require 'netlinx/compile/extension_discovery'

module NetLinx
  module Compile
    # The container for the script that runs when netlinx-compile is executed.
    class Script
      private_class_method :new
      
      class << self
        # Run the script.
        # @option kwargs [Array<String>] :argv A convenience to override ARGV,
        #   like for testing.
        def run(**kwargs)
          args = kwargs.fetch :argv, ARGV

          # Command line options.
          @options = OpenStruct.new \
            source: '',
            include_paths: [],
            use_workspace: false
          
          OptionParser.new do |opts|
            opts.banner = "Usage: netlinx-compile [options]"
            
            opts.on '-h', '--help', 'Display this help screen.' do
              puts opts
              exit
            end
            
            opts.on '-s', '--source FILE', 'Source file to compile.' do |v|
              @options.source = v
            end
            
            opts.on '-i', '--include [Path1,Path2]', Array, 'Additional include and module paths.' do |v|
              @options.include_paths = v
            end
            
            opts.on '-w', '--workspace', '--smart',
                    'Search up directory tree for a workspace',
                    'containing the source file.' do |v|
              @options.use_workspace = v
            end
            
          end.parse! args
          
          if @options.source.empty?
            puts "No source file specified.\nRun \"netlinx-compile -h\" for help."
            exit
          end
          
          # Find an ExtensionHandler for the given file.
          ExtensionDiscovery.discover
          source_file = File.expand_path @options.source
          handler = NetLinx::Compile::ExtensionDiscovery.get_handler source_file
          
          # If the handler is a workspace handler, go straight to compiling it.
          # Otherwise, if the use_workspace flag is true, search up through the
          # directory tree to try to find a workspace that includes the
          # specified source file.
          if (not handler.is_a_workspace?) && @options.use_workspace
            workspace_extensions = NetLinx::Compile::ExtensionDiscovery.workspace_extensions
            
            dir = File.expand_path '.'
            while dir != File.expand_path('..', dir) do
              workspaces = Dir["#{dir}/*.{#{workspace_extensions.join ','}}"]
              
              unless workspaces.empty?
                # TODO: Handle workspace file extension usurping logic here.
                
                new_source_file = workspaces.first
                new_handler = NetLinx::Compile::ExtensionDiscovery.get_handler new_source_file
                new_handler_class = new_handler.handler_class.new \
                  file: File.expand_path(new_source_file)
                
                # If supported by the new_handler, make sure the source_file is
                # included in the workspace before overwriting the old handler.
                overwrite_old_handler = false
                
                if new_handler_class.respond_to? :include?
                  overwrite_old_handler = true if new_handler_class.include? source_file
                else
                  # Workspace doesn't expose an interface to see if it
                  # includes the source file, so assume it does.
                  # Otherwise the user could have compiled without the
                  # workspace flag.
                  overwrite_old_handler = true
                end
                
                if overwrite_old_handler
                  source_file = new_source_file
                  handler = new_handler
                  handler_class = new_handler_class
                  break
                end
              end
              
              dir = File.expand_path '..', dir
            end
          end
          
          # Instantiate the class that can handle compiling of the file.
          handler_class = handler.handler_class.new \
            file: File.expand_path(source_file)
          
          result = handler_class.compile
          
          result.map {|r| r.to_s}
        end
        
      end
      
    end
  end
end