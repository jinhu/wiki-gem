require 'rugged'

class GitStore
  @@instance=nil
  # singleton

  def self.instance app_root
    if @@instance==nil
      @@instance = GitStore.new app_root

    end
    @@instance

  end

  def initialize app_root
    @data_root=app_root+"/data"
    @repo = Rugged::Repository.init_at(@data_root)
  end


  def get_hash(path)
    json = get_text path
    story= JSON.parse(json) if json
    git_item = path.sub(@data_root+"/", "")

    walker = Rugged::Walker.new(@repo)
    paths =[]
    walker.sorting(Rugged::SORT_TOPO | Rugged::SORT_REVERSE)
    walker.push(@repo.head.target)
    walker.each do |commit|
      # skip merges
      next if commit.parents.count != 1

      diffs = commit.parents[0].diff(commit)
      diffs.each_delta do |delta|
        if (delta.old_file[:path].include? git_item)
          paths += [commit.message]
        end

      end

    end
    {
        journal: paths,
        title: git_item,
        story: story
    }
  end


  def get_text(path)
    File.read path if File.exist? path
  end

  def self.get_blob(path)
    File.binread path if File.exist? path
  end

  ### PUT
  def put_hash(path, ruby_data, metadata={})
    if ruby_data
      json = JSON.pretty_generate(ruby_data[:story])
      put_text path, json, ruby_data[:journal]
    end
    ruby_data
  end

  def put_text(path, text, metadata=nil)
    # Note: metadata is ignored for filesystem storage
    # File.open(path, 'w') { |file| file.write text }
    # FileUtils.mkdir_p path
    git_item = path.sub(@data_root+"/", "")
    # oid = Rugged::Blob.from_workdir @repo, git_item
    oid = @repo.write(text, :blob)
    index = @repo.index
    index.read_tree(repo.head.target.tree)
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
    options[:message] = JSON.pretty_generate(metadata[-1])
    options[:parents] = @repo.empty? ? [] : [@repo.head.target].compact
    options[:update_ref] = 'HEAD'

    commit = Rugged::Commit.create(@repo, options)
    text
  end

  def self.put_blob(path, blob)
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

  def self.exists?(path)
    File.exists?(path)
  end

  def find(search)
    pages = annotated_pages farm_page.directory
    candidates = pages.select do |page|
      datasets = page[:story].select do |key, item|
        item['type']=='paragraph' && item['text'] && item['text'].index(search)
      end
      datasets.length > 0
    end
  end


  def data_dir(site)
    @site = site
    farm?(@data_root) ? File.join(@data_root, "farm", site) : @data_root
  end

  def farm_status(site=@site)
    status = File.join data_dir(site), "status"
    mkdir status
    status
  end

  def farm_page(site=@site)
    page = Page.new
    page.directory = File.join data_dir(site), "pages"
    page.default_directory = File.join APP_ROOT, "default-data", "pages"
    page.plugins_directory = File.join APP_ROOT, "node_modules"
    mkdir page.directory
    page
  end

  def identified? site=@site
    File.exists? "#{farm_status site}/open_id.identifier"
  end
  def claimed? site=@site
    File.exists? "#{farm_status site}/open_id.identity"
  end

  def identity
    default_path = File.join APP_ROOT, "default-data", "status", "local-identity"
    real_path = File.join farm_status, "local-identity"
    id_data = get_hash( real_path)[:story]
    id_data ||= put_hash(real_path, get_hash(default_path))
  end

  alias_method :get_page, :get_hash
  alias_method :put_page, :put_hash
end

