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
    @repo = Rugged::Repository.new(@data_root)
    if (@repo.head_unborn?)
      @repo = Rugged::Repository.init_at(@data_root)
    end
  end


  def get_hash(path)
    page = {}
    json = get_text path
    if json
      page['story']= JSON.parse(json)
    else
      page['story']= {}
    end
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
    page['journal']=paths
    page['title'] = git_item
    page
  end


  def get_text(path)
    File.read path if File.exist? path
  end

  def self.get_blob(path)
    File.binread path if File.exist? path
  end

  ### PUT
  def put_hash(path, ruby_data, metadata={})
    json = JSON.pretty_generate(ruby_data['story'])
    put_text path, json, ruby_data['journal']
    ruby_data
  end

  def put_text(path, text, metadata=nil)
    # Note: metadata is ignored for filesystem storage
    File.open(path, 'w') { |file| file.write text }
    # FileUtils.mkdir_p path
    git_item = path.sub(@data_root+"/", "")
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

  alias_method :get_page, :get_hash
  alias_method :put_page, :put_hash
end

