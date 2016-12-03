require 'rugged'

class GitStore < Store

  # singleton

  def self.instance app_root
    if @@instance==nil
      @@instance = GitStore.new app_root

    end
    @@instance

  end

  def initialize app_root
    @app_root=root+"/data"
    @repo = Rugged::Repository.new(@app_root)
    if (@repo.head_unborn?)
      @repo = Rugged::Repository.init_at(@app_root)
    end
  end

  alias_method :get_page, :get_hash
  alias_method :put_page, :put_hash


  def get_hash(path)
    json = get_text path
    JSON.parse json if json
  end


  def get_text(path)
    File.read path if File.exist? path
  end

  def get_blob(path)
    File.binread path if File.exist? path
  end

  ### PUT
  def put_hash(path, ruby_data, metadata={})
    json = JSON.pretty_generate(ruby_data['story'])
    put_text path, json, metadata
    ruby_data
  end

  def put_text(path, text, metadata=nil)
    # Note: metadata is ignored for filesystem storage
    File.open(path, 'w') { |file| file.write text }
    # FileUtils.mkdir_p path
    git_item = path.sub(@app_root+"/", "")
    oid = Rugged::Blob.from_workdir @repo, git_item
    index = @repo.index

    index.add(:path => git_item, :oid => oid, :mode => 0100644)
    index.write
    options = {}
    options[:tree] = index.write_tree(@repo)

    options[:author] = {:email => "fud@waka.alt",
                        :name => 'Test Author',
                        :time => Time.now}
    options[:committer] = {:email => "fud@waka.alt",
                           :name => 'Test Author',
                           :time => Time.now}
    options[:message] = "write #{git_item}"
    options[:parents] = @repo.empty? ? [] : [@repo.head.target].compact
    options[:update_ref] = 'HEAD'

    commit = Rugged::Commit.create(@repo, options)
    text
  end

  def put_blob(path, blob)
    File.open(path, 'wb') { |file| file.write blob }
    blob
  end

  ### COLLECTIONS

  def annotated_pages(pages_dir)
    Dir.foreach(pages_dir).reject { |name| name =~ /^\./ }.collect do |name|
      page = get_page(File.join pages_dir, name)
      page.merge!({
                      'name' => name,
                      'updated_at' => File.new("#{pages_dir}/#{name}").mtime
                  })
    end
  end


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

