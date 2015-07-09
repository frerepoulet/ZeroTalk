class TopicList extends Class
	constructor: ->
		@thread_sorter = null
		@parent_topic_uri = undefined
		@topic_parent_uris = {}


	actionList: (parent_topic_id, parent_topic_user_address) ->
		$(".topics-loading").cssLater("top", "0px", 200)

		# Topic group listing
		if parent_topic_id
			$(".topics-title").html("&nbsp;")
			@parent_topic_uri = "#{parent_topic_id}_#{parent_topic_user_address}"

			# Update visited info
			Page.local_storage["topic.#{parent_topic_id}_#{parent_topic_user_address}.visited"] = Time.timestamp()
			Page.cmd "wrapperSetLocalStorage", Page.local_storage
		else
			$(".topics-title").html("Newest topics")

		@loadTopics("noanim")

		# Show create new topic form
		$(".topic-new-link").on "click", =>
			$(".topic-new").fancySlideDown()
			$(".topic-new-link").slideUp()
			return false

		# Create new topic
		$(".topic-new .button-submit").on "click", =>
			@submitCreateTopic()
			return false


	loadTopics: (type="list", cb=false) ->
		@logStart "Load topics..."
		topic_group_action = {}
		topic_group_after = {}
		if @parent_topic_uri
			where = "WHERE parent_topic_uri = '#{@parent_topic_uri}' OR row_topic_uri = '#{@parent_topic_uri}'"
		else
			where = ""
		last_elem = $(".topics-list .topic.template")
		
		query = """
			SELECT 
			 COUNT(comment_id) AS comments_num, MAX(comment.added) AS last_comment,
			 topic.*,
			 topic_creator_user.value AS topic_creator_user_name,
			 topic_creator_content.directory AS topic_creator_address,
			 topic.topic_id || '_' || topic_creator_content.directory AS row_topic_uri,
			 (SELECT COUNT(*) FROM topic_vote WHERE topic_vote.topic_uri = topic.topic_id || '_' || topic_creator_content.directory)+1 AS votes
			FROM topic 
			LEFT JOIN json AS topic_creator_json ON (topic_creator_json.json_id = topic.json_id)
			LEFT JOIN json AS topic_creator_content ON (topic_creator_content.directory = topic_creator_json.directory AND topic_creator_content.file_name = 'content.json')
			LEFT JOIN keyvalue AS topic_creator_user ON (topic_creator_user.json_id = topic_creator_content.json_id AND topic_creator_user.key = 'cert_user_id')
			LEFT JOIN comment ON (comment.topic_uri = row_topic_uri)
			#{where}
			GROUP BY topic.topic_id, topic.json_id
			ORDER BY CASE WHEN last_comment THEN last_comment ELSE topic.added END DESC
		"""

		Page.cmd "dbQuery", [query], (topics) =>
			for topic in topics
				topic_uri = topic.row_topic_uri
				# Save the latest action of topic group
				if topic.parent_topic_uri and not topic_group_action[topic.parent_topic_uri] 
					if topic.last_comment
						topic_group_action[topic.parent_topic_uri] = topic.last_comment
					else
						topic_group_action[topic.parent_topic_uri] = topic.added
					topic_group_after[topic.parent_topic_uri] = last_elem

				# Skip it if we not in the subcategory
				if topic.parent_topic_uri and @parent_topic_uri != topic.parent_topic_uri then continue 

				# Parent topic for group that we currently listing
				if @parent_topic_uri and topic_uri == @parent_topic_uri
					topic_parent = topic
					continue # Dont display it

				if topic.type == "group" then topic.last_comment = topic_group_action[topic_uri]
				
				elem = $("#topic_"+topic_uri)
				if elem.length == 0 # Create if not exits yet
					elem = $(".topics-list .topic.template").clone().removeClass("template").attr("id", "topic_"+topic_uri)
					if type != "noanim" then elem.cssSlideDown()

				if topic.type == "group"
					if topic_group_after[topic_uri] # Has after
						elem.insertBefore topic_group_after[topic.row_topic_uri].nextAll(":not(.topic-group):first") # Add before the next non-topic group
						# Sorting messed, dont insert next item after it: Do not update last elem
					else
						elem.insertAfter(last_elem)
						last_elem = elem
				else
					elem.insertAfter(last_elem)
					last_elem = elem
				
				
				@applyTopicData(elem, topic)

			Page.addInlineEditors()


			$("body").css({"overflow": "auto", "height": "auto"}) # Auto height body

			@logEnd "Load topics..."
			
			# Hide loading
			if parseInt($(".topics-loading").css("top")) > -30 # Loading visible, animate it
				$(".topics-loading").css("top", "-30px")
			else
				$(".topics-loading").remove()

			# Set sub-title listing title
			if @parent_topic_uri
				$(".topics-title").html("<span class='parent-link'><a href='?Main'>Main</a> &rsaquo;</span> #{topic_parent.title}")

			$(".topics").css("opacity", 1)

			if cb then cb()


	applyTopicData: (elem, topic, type="list") ->
		title_hash = Text.toUrl(topic.title)
		topic_uri = topic.row_topic_uri
		$(".title .title-link", elem).text(topic.title)
		$(".title .title-link, a.image, .comment-num", elem).attr("href", "?Topic:#{topic_uri}/#{title_hash}")
		elem.data "topic_uri", topic_uri

		# Get links in body
		body = topic.body
		url_match = body.match /http[s]{0,1}:\/\/[^"', $]+/
		if topic.type == "group" # Group type topic
			$(elem).addClass("topic-group")
			$(".image .icon", elem).removeClass("icon-topic-chat").addClass("icon-topic-group")
			$(".link", elem).css("display", "none")
			#$(".info", elem).css("display", "none")
			$(".title .title-link, a.image, .comment-num", elem).attr("href", "?Topics:#{topic_uri}/#{title_hash}")
		else if url_match # Link type topic
			url = url_match[0]
			if type != "show" then body = body.replace /http[s]{0,1}:\/\/[^"' $]+$/g, "" # Remove links from end
			$(".image .icon", elem).removeClass("icon-topic-chat").addClass("icon-topic-link")
			$(".link", elem).css("display", "").attr "href", Text.fixLink(url)
			$(".link .link-url", elem).text(url)
		else # Normal type topic
			$(".image .icon", elem).removeClass("icon-topic-link").addClass("icon-topic-chat")
			$(".link", elem).css("display", "none")

		if type == "show" # Markdon syntax at topic show
			$(".body", elem).html Text.toMarked(body, {"sanitize": true})
		else # No format on listing
			$(".body", elem).text body

		# Last activity and comment num
		if type != "show"
			last_action = Math.max(topic.last_comment, topic.added)
			if topic.type == "group"
				$(".comment-num", elem).text "last activity"
				$(".added", elem).text Time.since(last_action)
			else if topic.comments_num > 0
				$(".comment-num", elem).text "#{topic.comments_num} comment"
				$(".added", elem).text "last "+Time.since(last_action)
			else
				$(".comment-num", elem).text "0 comments"
				$(".added", elem).text Time.since(last_action)
		
		# Creator address and user name
		$(".user_name", elem)
			.text(topic.topic_creator_user_name.replace(/@.*/, ""))
			.attr("title", topic.topic_creator_user_name+": "+topic.topic_creator_address)
		
		# Apply topic score
		if User.my_topic_votes[topic_uri] # Voted on topic
			$(".score-inactive .score-num", elem).text topic.votes-1
			$(".score-active .score-num", elem).text topic.votes
			$(".score", elem).addClass("active")
		else # Not voted on it
			$(".score-inactive .score-num", elem).text topic.votes
			$(".score-active .score-num", elem).text topic.votes+1
		$(".score", elem).off("click").on "click", @submitTopicVote
		# Visited
		visited = Page.local_storage["topic.#{topic_uri}.visited"]
		if not visited
			elem.addClass("visit-none")
		else if visited < last_action
			elem.addClass("visit-newcomment")
		
		if type == "show" then $(".added", elem).text Time.since(topic.added)


		# My topic
		if topic.topic_creator_address == Page.site_info.auth_address
			$(elem).attr("data-object", "Topic:#{topic_uri}").attr("data-deletable", "yes")
			$(".title .title-link", elem).attr("data-editable", "title").data("content", topic.title)
			$(".body", elem).attr("data-editable", "body").data("content", topic.body)


	submitCreateTopic: ->
		# if not Page.hasOpenPort() then return false
		if not Page.site_info.cert_user_id # No selected cert
			Page.cmd "wrapperNotification", ["info", "Please, your choose account before creating a topic."]
			return false

		title = $(".topic-new #topic_title").val()
		body = $(".topic-new #topic_body").val()
		#if not body then return $(".topic-new #topic_body").focus()
		if not title then return $(".topic-new #topic_title").focus()

		$(".topic-new .button-submit").addClass("loading")
		User.getData (data) =>
			topic = {
				"topic_id": data.next_topic_id,
				"title": title,
				"body": body,
				"added": Time.timestamp()
			}
			if @parent_topic_uri then topic.parent_topic_uri = @parent_topic_uri
			data.topic.push topic
			data.next_topic_id += 1
			User.publishData data, (res) =>
				$(".topic-new .button-submit").removeClass("loading")
				$(".topic-new").slideUp()
				$(".topic-new-link").slideDown()
				setTimeout (=>
					@loadTopics()
				), 600
				$(".topic-new #topic_body").val("")
				$(".topic-new #topic_title").val("")


	submitTopicVote: (e) =>
		if not Page.site_info.cert_user_id # No selected cert
			Page.cmd "wrapperNotification", ["info", "Please, your choose account before upvoting."]
			return false
			
		elem = $(e.currentTarget)
		elem.toggleClass("active").addClass("loading")
		inner_path = "data/users/#{User.my_address}/data.json"
		User.getData (data) =>
			data.topic_vote ?= {}
			topic_uri = elem.parents(".topic").data("topic_uri")
			
			if elem.hasClass("active")
				data.topic_vote[topic_uri] = 1
			else
				delete data.topic_vote[topic_uri]
			User.publishData data, (res) =>
				elem.removeClass("loading")
		return false
			

window.TopicList = new TopicList()