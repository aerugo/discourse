require 'nokogiri'

require "mysql2"
require File.expand_path(File.dirname(__FILE__) + "/base.rb")
require File.expand_path(File.dirname(__FILE__) + "/drupal.rb")


# Edit the constants and initialize method for your import data.

class ImportScripts::DrupalER < ImportScripts::Drupal

  DRUPAL_FILES_DIR = ENV['DRUPAL_FILES_DIR']


  def execute

    # # You'll need to edit the following query for your Drupal install:
    # #
    # #   * Drupal allows duplicate category names, so you may need to exclude some categories or rename them here.
    # #   * Table name may be term_data.
    # #   * May need to select a vid other than 1.
    # create_categories(categories_query) do |c|
    #   {id: c['tid'], name: c['name'], description: c['description']}
    # end

    # User.where.not("email = 'admin@example.com' or id = -1 or id = -2").delete_all
    # UserCustomField.delete_all

    #     Topic.delete_all
    #     TopicCustomField.delete_all
    #
    #     Post.delete_all
    #     PostCustomField.delete_all
    #
    create_users

    create_post_and_wiki_topics

    create_challenge_response_topics

    create_replies

    # Permalink.delete_all

    process_posts

    # begin
    #   create_admin(email: 'admin@example.com', username: UserNameSuggester.suggest('admin'))
    # rescue => e
    #   puts '', "Failed to create admin user"
    #   puts e.message
    # end

  end


  def create_users
    puts '', 'creating users...'

    sql = <<-SQL
      SELECT u.uid id, u.name, u.mail email, u.created, fb.field_bio_value bio_raw, fa.field_agegroup_value agegroup,
        bi.field_i_m_based_in_value location, fu.field_facebook_url_url facebook_url, tu.field_twitter_url_url twitter_url,
        lu.field_linkedin_url_url linkedin_url, wu.field_website_url_url website_url, fc.field_first_contact_value first_contact,
        co.field_consent_opencare_value consent_opencare_date, fm.filename profile_picture
      FROM users AS u
        LEFT JOIN field_data_field_bio AS fb on u.uid = fb.entity_id
        LEFT JOIN field_data_field_agegroup AS fa on u.uid = fa.entity_id
        LEFT JOIN field_data_field_i_m_based_in AS bi on u.uid = bi.entity_id
        LEFT JOIN field_data_field_facebook_url AS fu on u.uid = fu.entity_id
        LEFT JOIN field_data_field_twitter_url AS tu on u.uid = tu.entity_id
        LEFT JOIN field_data_field_linkedin_url AS lu on u.uid = lu.entity_id
        LEFT JOIN field_data_field_website_url AS wu on u.uid = wu.entity_id
        LEFT JOIN field_data_field_first_contact AS fc on u.uid = fc.entity_id
        LEFT JOIN field_data_field_consent_opencare AS co on u.uid = co.entity_id
        LEFT JOIN file_managed AS fm on u.picture = fm.fid
      WHERE
        u.uid != 0 AND
        (fb.entity_type = 'user' or fb.entity_type is null) AND
        (fa.entity_type = 'user' or fa.entity_type is null) AND
        (bi.entity_type = 'user' or bi.entity_type is null) AND
        (fu.entity_type = 'user' or fu.entity_type is null) AND
        (tu.entity_type = 'user' or tu.entity_type is null) AND
        (lu.entity_type = 'user' or lu.entity_type is null) AND
        (wu.entity_type = 'user' or wu.entity_type is null) AND
        (fc.entity_type = 'user' or fc.entity_type is null) AND
        (co.entity_type = 'user' or co.entity_type is null)
    SQL
    super(@client.query(sql)) do |row|
      {
        id: row['id'],
        username: row['name'], #.parameterize.underscore,
        #email: row['email'],
        email: "#{rand(36**12).to_s(36)}@example.com",
        created_at: Time.zone.at(row['created']),
        bio_raw: row['bio_raw'],
        website: row['website_url'],
        location: row['location'],
        custom_fields: {
          agegroup: row['agegroup'],
          facebook_url: row['facebook_url'],
          twitter_url: row['twitter_url'],
          linkedin_url: row['linkedin_url'],
          first_contact: row['first_contact'],
          consent_opencare: row['consent_opencare_date'],
          import_id: row['id']
        },
        post_create_action: proc do |user|
          if row['profile_picture'].present? && user.uploaded_avatar_id.blank?
            begin
              path = "#{DRUPAL_FILES_DIR}/pictures/#{row['profile_picture']}"
              upload = create_upload(user.id, path, row['profile_picture'])
              if upload.present? && upload.persisted?
                user.import_mode = false
                user.create_user_avatar
                user.user_avatar.update(custom_upload_id: upload.id)
                user.update(uploaded_avatar_id: upload.id)
                user.refresh_avatar
              else
                puts 'Upload failed!'
              end
            rescue SystemCallError => err
              puts "Could not import avatar: #{err.message}"
            end
          end
        end
      }
    end
  end


  def create_post_and_wiki_topics
    puts '', 'creating post and wiki topics...'

    # create_category({
    #                   name: 'Post',
    #                   user_id: -1,
    #                   description: "Articles from the blog"
    #                 }, nil) unless Category.find_by_name('Blog')

    sql = <<-SQL
      SELECT
        n.nid nid,
        n.type type,
        n.uid uid,
        n.status status,
        n.created created,
        n.changed changed,
        tf.title_field_value title,
        db.body_value content
      FROM node AS n
        LEFT JOIN field_data_title_field AS tf on n.nid = tf.entity_id
        LEFT JOIN field_data_body AS db on n.nid = db.entity_id
      WHERE
        n.type IN('post', 'wiki')
      ORDER BY n.nid DESC
      LIMIT 50
      OFFSET 500
    SQL

    results = @client.query(sql, cache_rows: false)

    create_posts(results) do |row|
      {
        id: "nid:#{row['nid']}",
        user_id: user_id_from_imported_user_id(row['uid']) || -1,
        title: row['title'].try(:strip),
        raw: row['content'],
        created_at: Time.zone.at(row['created']),
        updated_at: Time.zone.at(row['changed']),
        custom_fields: {import_id: "nid:#{row['nid']}"}
        # category: 'Blog',
        # visible: row['status'].to_i == 0 ? false : true
        # pinned_at: row['sticky'].to_i == 1 ? Time.zone.at(row['created']) : nil,
      }
    end
  end


  def create_challenge_response_topics
    puts '', 'creating challenge response topics...'

    # create_category({
    #                   name: 'Post',
    #                   user_id: -1,
    #                   description: "Articles from the blog"
    #                 }, nil) unless Category.find_by_name('Blog')

    sql = <<-SQL
      SELECT
        n.nid nid,
        n.uid uid,
        tf.title_field_value title,
        db.body_value content,
        n.status status,
        n.created created,
        n.changed changed,
        n.type type
      FROM node AS n
        LEFT JOIN field_data_title_field AS tf on n.nid = tf.entity_id
        LEFT JOIN field_data_body AS db on n.nid = db.entity_id
      WHERE
        n.type IN('post', 'wiki')
    SQL

    results = @client.query(sql, cache_rows: false)


    create_posts(results) do |row|
      {
        id: "nid:#{row['nid']}",
        user_id: user_id_from_imported_user_id(row['uid']) || -1,
        title: row['title'].try(:strip),
        raw: row['content'],
        created_at: Time.zone.at(row['created']),
        updated_at: Time.zone.at(row['changed']),
        custom_fields: {import_id: "nid:#{row['nid']}"}
        # category: 'Blog',
        # visible: row['status'].to_i == 0 ? false : true
        # pinned_at: row['sticky'].to_i == 1 ? Time.zone.at(row['created']) : nil,
      }
    end
  end


  def create_replies
    puts '', "creating replies in topics..."

    total_count = @client.query("
        SELECT COUNT(*) count
          FROM comment c,
               node n
         WHERE n.nid = c.nid
           AND c.status = 1
           AND n.type IN ('challenge_response', 'post', 'wiki');").first['count']

    batch_size = 1000

    batches(batch_size) do |offset|
      results = @client.query("
        SELECT c.cid, c.pid, c.nid, c.uid, c.created, c.subject,
               f.comment_body_value body
          FROM comment c,
               field_data_comment_body f,
               node n
         WHERE c.cid = f.entity_id
           AND n.nid = c.nid
           AND c.status = 1
           AND n.type IN ('challenge_response', 'post', 'wiki')
          ORDER BY c.cid
         LIMIT #{batch_size}
        OFFSET #{offset};
      ", cache_rows: false)

      break if results.size < 1

      next if all_records_exist? :posts, results.map { |p| "cid:#{p['cid']}" }

      create_posts(results, total: total_count, offset: offset) do |row|
        topic_mapping = topic_lookup_from_imported_post_id("nid:#{row['nid']}")
        if topic_mapping && (topic_id = topic_mapping[:topic_id])
          content = if ActionView::Base.full_sanitizer.sanitize(row['body']).start_with?(row['subject'])
                      row['body']
                    else
                      "<b>#{row['subject']}</b>\n\n"+row['body']
                    end
          h = {
            id: "cid:#{row['cid']}",
            topic_id: topic_id,
            user_id: user_id_from_imported_user_id(row['uid']) || -1,
            raw: content,
            created_at: Time.zone.at(row['created']),
          }
          if row['pid']
            parent = topic_lookup_from_imported_post_id("cid:#{row['pid']}")
            h[:reply_to_post_number] = parent[:post_number] if parent and parent[:post_number] > 1
          end
          h
        else
          puts "No topic found for comment #{row['cid']}"
          nil
        end
      end

    end
  end


  def process_posts
    puts '', 'processing posts...'

    Post.find_each do |post|
      next if post.raw.nil?

      # Extract all links.
      links = []
      doc = Nokogiri::HTML.fragment(post.raw)
      doc.css('a').each do |a|
        if a['href'].present? && a['href'][0] != '#'
          # Permalink.create(url: '/discussion/12345', topic_id: 987)
          Permalink.create(url: a['href']) rescue nil
          links << a['href']
        end
      end

      # Upload images.
      doc.css('img').each do |img|
        if img['src'].present?
          Permalink.create(url: img['src']) rescue nil
          if '/sites/edgeryders.eu/files/'.in?(img['src'])
            filename = File.join(DRUPAL_FILES_DIR, 'inline-images', File.basename(img['src']))
            if File.exists?(filename)
              upload = create_upload(post.user_id, filename, File.basename(filename))
              if upload.nil? || upload.invalid?
                puts "Upload not valid :(  #{filename}"
                puts upload.errors.inspect if upload
              else
                post.raw.gsub!(img['src'], upload.url)
              end
            else
              puts "Image doesn't exist: #{filename}"
            end
          end
        end
      end

      # HTML cleanup.
      post.raw.gsub!(' dir="ltr"', '')
      post.raw.gsub!('<p>&nbsp;</p>', '')
      post.raw.gsub!('<li>&nbsp;</li>', '')
      post.raw.gsub!("<li>\n", '<li>')
      post.raw.gsub!('<p>', '')
      post.raw.gsub!('</p>', '')
      post.raw.gsub!(%r~<br\s*\/?>~, "\n")
      # Replace three or more consecutive linebreaks with two.
      post.raw.gsub!(/\n{3,}/, "\n\n")

      post.save!
    end

  end


end

if __FILE__==$0
  ImportScripts::DrupalER.new.perform
end