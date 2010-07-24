module Diaspora
   module Webhooks
      def self.included(klass)
        klass.class_eval do
          include ROXML
          require 'message_handler'
          @@queue = MessageHandler.new

          def notify_people
            if self.person_id == User.owner.id
              push_to(people_with_permissions)
            end
          end

          def subscribe_to_ostatus(feed_url)
            @@queue.add_subscription_request(feed_url)
            @@queue.process
          end

          def unsubscribe_from_ostatus(feed_url)
            @@queue.add_hub_unsubscribe_request(self.destination_url, self.callback_url+'hubbub', feed_url)
            @@queue.process
          end

          def push_to(recipients)
            @@queue.add_hub_notification(APP_CONFIG[:pubsub_server], User.owner.url + self.class.to_s.pluralize.underscore + '.atom')

            unless recipients.empty?
              recipients.map!{|x| x = x.url + "receive/"}  
              xml = self.class.build_xml_for([self])
              Rails.logger.info("Adding xml for #{self} to message queue to #{recipients}")
              @@queue.add_post_request( recipients, xml )
            end
            @@queue.process
          end

          def push_to_url(url)
            hook_url = url + "receive/"
            xml = self.class.build_xml_for([self])
            Rails.logger.info("Adding xml for #{self} to message queue to #{url}")
            @@queue.add_post_request( [hook_url], xml )
            @@queue.process
          end

          def prep_webhook
            "<post>#{self.to_xml.to_s}</post>"
          end

          def people_with_permissions
             Person.friends.all
          end

          def self.build_xml_for(posts)
            xml = "<XML>"
            xml += "\n <posts>"
            posts.each {|x| xml << x.prep_webhook}
            xml += "</posts>"
            xml += "</XML>"
          end

        end
      end
    end

    module XML

      def self.generate(opts= {})
        xml = Generate::headers(opts[:current_url])
        xml << Generate::author
        xml << Generate::endpoints
        xml << Generate::subject
        xml << Generate::entries(opts[:objects])
        xml << Generate::footer
      end

      module Generate
        def self.headers(current_url)
          #this is retarded
          @@user = User.owner
          <<-XML
  <?xml version="1.0" encoding="UTF-8"?>
  <feed xml:lang="en-US" xmlns="http://www.w3.org/2005/Atom" xmlns:thr="http://purl.org/syndication/thread/1.0" xmlns:georss="http://www.georss.org/georss" xmlns:activity="http://activitystrea.ms/spec/1.0/" xmlns:media="http://purl.org/syndication/atommedia" xmlns:poco="http://portablecontacts.net/spec/1.0" xmlns:ostatus="http://ostatus.org/schema/1.0" xmlns:statusnet="http://status.net/schema/api/1/">
  <generator uri="http://joindiaspora.com/">Diaspora</generator>
  <id>#{current_url}</id>
  <title>Stream</title>
  <subtitle>its a stream </subtitle>
  <updated>#{Time.now.xmlschema}</updated>
          XML
        end

        def self.author
          <<-XML
  <author>
  <name>#{@@user.real_name}</name>
  <uri>#{@@user.url}</uri>
  </author>
          XML
        end

        def self.endpoints
            <<-XML
   <link href="#{APP_CONFIG[:pubsub_server]}" rel="hub"/>
            XML
        end

        def self.subject
          <<-XML
  <activity:subject>
  <activity:object-type>http://activitystrea.ms/schema/1.0/person</activity:object-type>
  <id>#{@@user.url}</id>
  <title>#{@@user.real_name}</title>
  <link rel="alternative" type="text/html" href="#{@@user.url}"/>
  </activity:subject>
          XML
        end

        def self.entries(objects)
          xml = ""
          if objects.respond_to? :each
            objects.each {|x| xml << self.entry(x)}
          else
            xml << self.entry(objects)
          end
          xml
        end

        def self.entry(object)
          eval "#{object.class}_build_entry(object)"
        end

        def self.StatusMessage_build_entry(status_message)
          <<-XML
  <entry>
  <activity:verb>http://activitystrea.ms/schema/1.0/post</activity:verb>
  <title>#{status_message.message}</title>
  <link rel="alternate" type="text/html" href="#{@@user.url}status_messages/#{status_message.id}"/>
  <id>#{@@user.url}status_messages/#{status_message.id}</id>
  <published>#{status_message.created_at.xmlschema}</published>
  <updated>#{status_message.updated_at.xmlschema}</updated>
  </entry>
          XML
        end

        def self.Bookmark_build_entry(bookmark)
          <<-XML
  <entry>
  <activity:verb>http://activitystrea.ms/schema/1.0/post</activity:verb>
  <title>#{bookmark.title}</title>
  <link rel="alternate" type="text/html" href="#{@@user.url}bookmarks/#{bookmark.id}"/>
  <link rel="related" type="text/html" href="#{bookmark.link}"/>
  <id>#{@@user.url}bookmarks/#{bookmark.id}</id>
  <published>#{bookmark.created_at.xmlschema}</published>
  <updated>#{bookmark.updated_at.xmlschema}</updated>
  </entry>
          XML
        end


        def self.Blog_build_entry(blog)
          <<-XML
  <entry>
  <activity:verb>http://activitystrea.ms/schema/1.0/post</activity:verb>
  <title>#{blog.title}</title>
  <content>#{blog.body}</content>
  <link rel="alternate" type="text/html" href="#{@@user.url}blogs/#{blog.id}"/>
  <id>#{@@user.url}blogs/#{blog.id}</id>
  <published>#{blog.created_at.xmlschema}</published>
  <updated>#{blog.updated_at.xmlschema}</updated>
  </entry>
          XML
        end

        def self.footer
          <<-XML.strip
  </feed>
          XML
        end
      end
    end
end