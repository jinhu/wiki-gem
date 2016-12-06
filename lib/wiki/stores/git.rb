require 'rugged'

class GitStore < Store
  class << self

    def get_text(path)
      story=[]
      journal =[]
      @repo = Rugged::Repository.init_at(@app_root+"/data/")
      git_item = path.sub(@app_root+"/data/", "")
      if File.exist? path
        json = File.read path
        oid = Rugged::Blob.from_workdir @repo, git_item
        if json && json.size > 0
          story= JSON.parse(json)

          walker = Rugged::Walker.new(@repo)
          walker.sorting(Rugged::SORT_TOPO | Rugged::SORT_REVERSE)
          walker.push(@repo.head.target)
          walker.each do |commit|
            # skip merges
            next if commit.parents.count != 1

            diffs = commit.parents[0].diff(commit)
            diffs.each_delta do |delta|
              if (delta.old_file[:path].include? git_item)
                journal += [JSON.parse(commit.message)]
              end

            end

          end
        end
      end

      JSON.pretty_generate({
                               'journal': journal,
                               'title': git_item,
                               'story': story
                           })
    end

    def get_blob(path)
      File.binread path if File.exist? path
    end

    def put_text(path, text, metadata=nil)
      @repo = Rugged::Repository.init_at(@app_root+"/data/")
      git_item = path.sub(@app_root+"/data/", "")
      data = JSON.parse text
      File.open(path, 'w') { |file| file.write JSON.pretty_generate(data['story']) }
      oid = Rugged::Blob.from_workdir @repo, git_item
      index = @repo.index
      index.read_tree(@repo.head.target.tree)
      index.add(:path => git_item, :oid => oid, :mode => 0100644)
      index.write
      options = {}
      options[:tree] = index.write_tree(@repo)
      #
      # options[:author] = {:email => "fud@waka.alt",
      #                     :name => 'Test Author',
      #                     :time => Time.now}
      # options[:committer] = {:email => "fud@waka.alt",
      #                        :name => 'Test Author',
      #                        :time => Time.now}
      options[:message] = JSON.pretty_generate(data['journal'][-1])
      options[:parents] = @repo.empty? ? [] : [@repo.head.target].compact
      options[:update_ref] = 'HEAD'

      commit = Rugged::Commit.create(@repo, options)
      text
    end

    def put_blob(path, blob)
      File.open(path, 'wb') { |file| file.write blob }
      blob
    end


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

    alias_method :get_page, :get_hash
    alias_method :put_page, :put_hash
  end
end
