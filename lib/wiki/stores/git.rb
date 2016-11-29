require 'rugged'

class GitStore < Store
class << self

  def app_root= root
    @app_root=root
    @repo = Rugged::Repository.new(root)
    if(@repo.head_unborn?)
      @repo = Rugged::Repository.init_at(root)
    end
  end

    ### GET

    def get_text(path)
      File.read path if File.exist? path
    end

    def get_blob(path)
      File.binread path if File.exist? path
    end

    ### PUT

    def put_text(path, text, metadata=nil)
      # Note: metadata is ignored for filesystem storage
      File.open(path, 'w'){ |file| file.write text }
      oid = Rugged::Blob.from_workdir @repo, path.sub(@app_root,"")
      index = @repo.index

      index.add(:path => name, :oid => oid, :mode => 0100644)
      index.write
      options = {}
      options[:tree] = index.write_tree(@repo)

      options[:author] = {  :email => "testuser@github.com",
                            :name => 'Test Author',
                            :time => Time.now }
      options[:committer] = { :email => "testuser@github.com",
                              :name => 'Test Author',
                              :time => Time.now }
      options[:message] =  "write #{ name }"
      options[:parents] = @repo.empty? ? [] : [ @repo.head.target ].compact
      options[:update_ref] = 'HEAD'

      commit = Rugged::Commit.create(@repo, options)
      text
    end

    def put_blob(path, blob)
      File.open(path, 'wb'){ |file| file.write blob }
      blob
    end

    ### COLLECTIONS

    def annotated_pages(pages_dir)
      Dir.foreach(pages_dir).reject{|name|name =~ /^\./}.collect do |name|
        page = get_page(File.join pages_dir, name)
        page.merge!({
          'name' => name,
          'updated_at' => File.new("#{pages_dir}/#{name}").mtime
        })
      end
    end

    ### UTILITY

    def farm?(data_root)
      ENV['FARM_MODE'] || File.exists?(File.join data_root, "farm")
    end

    def mkdir(directory)
      FileUtils.mkdir_p directory
    end

    def exists?(path)
      File.exists?(path)
    end
  end
end
