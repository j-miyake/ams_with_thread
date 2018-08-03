This is a Rails app to show a thread unsafe behavior of [ActiveModelSerializers](https://github.com/rails-api/active_model_serializers).

ActiveModelSerializers does not work properly when processing resources concurrently with multi threading.
When multiple thread are serializing concurrently, a resource to be serialized can be replaced with another resource by another thread. This is because ActiveModelSerializers stores resource instances in serializer classes, the stored resources are shared among threads, and this produces totally unexpected results.


### Setup
```sh
$ git clone git@github.com:johnny-miyake/ams_with_thread.git
$ cd ams_with_thread/
$ bundle install
$ bundle exec rake db:create db:migrate db:seed
```
```ruby
$ rails c
irb(main):001:0> Post.first
=> #<Post id: 1, title: "post1", body: "This is post1!", created_at: "2018-08-03 09:00:52", updated_at: "2018-08-03 09:00:52">

irb(main):002:0> Post.first.comments.to_a
=> [#<Comment id: 1, body: "This is a comment of post1", post_id: 1, created_at: "2018-08-03 09:00:52", updated_at: "2018-08-03 09:00:52">]

irb(main):003:0> Post.second             
=> #<Post id: 2, title: "post2", body: "This is post2!", created_at: "2018-08-03 09:00:52", updated_at: "2018-08-03 09:00:52">

irb(main):004:0> Post.second.comments.to_a
=> [#<Comment id: 2, body: "This is a comment of post2", post_id: 2, created_at: "2018-08-03 09:00:52", updated_at: "2018-08-03 09:00:52">]
```

### Example1: with Puma (a thread-based web server)
Puma concurrently processes multiple requests using multi-threading. This example shows that a request replaces a resource which is being used by another concurrent request.

Threr are two models; `Post` and `Comment`,
```ruby
# app/models/post.rb
class Post < ApplicationRecord
  has_many :comments
end

# app/models/comment.rb
class Comment < ApplicationRecord                                                                                         
  belongs_to :post                                                                                                         
end
```

and two serializers; `PostSerializer` and `CommentSerializer`.
```ruby
# app/serializers/post_serializer.rb
class PostSerializer < ActiveModel::Serializer
  attributes :id, :title, :body
  has_many :comments, serializer: CommentSerializer do
    sleep 3
    object.comments
  end
end

# app/serializers/comment_serializer.rb
class CommentSerializer < ActiveModel::Serializer
  attributes :id, :body
  has_one :post
end 
```

Then the thread unsafe behavior can be reproduced like below.

1. Launch Puma with `bundle exec rails s`
1. Open your browser
1. Open http://localhost:3000/posts/1 in a tab
1. Open http://localhost:3000/posts/2 in another tab
1. Reload both tabs within 3 seconds, and you'll get the following result

##### tab1
![tab1](https://github.com/johnny-miyake/ams_with_thread/wiki/images/tab1.png)
##### tab2
![tab2](https://github.com/johnny-miyake/ams_with_thread/wiki/images/tab2.png)


### Example2: with rails runner
The behavior also can be reproduced without browser.

Adding a class method like below,
```ruby
class Post < ApplicationRecord
  has_many :comments

  class << self
    def concurrent_serialization
      posts = {}
      t1 = Thread.new{posts[:first] =  PostSerializer.new(Post.first, {}).to_json}
      t2 = Thread.new{posts[:second] = PostSerializer.new(Post.second, {}).to_json}
      t1.join
      t2.join
      pp posts
    end
  end
end
```
running the method results that serialized two posts both have a same comment.
```sh
$ bundle exec rails runner "Post.concurrent_serialization"
{:first=>
  "{\"id\":1,\"title\":\"post1\",\"body\":\"This is post1!\",\"comments\":[{\"id\":1,\"body\":\"This is a comment of post1\"}]}",
 :second=>
  "{\"id\":2,\"title\":\"post2\",\"body\":\"This is post2!\",\"comments\":[{\"id\":1,\"body\":\"This is a comment of post1\"}]}"}
```

### The cause
ActiveModelSerializers stores reflection instances in a class variable of a serializer class. Each reflection instance holds a resource instance in `@object`. Because of this, the resource instance can be referred or be overwritten by another thread.

First, `ActiveModel::Serializer#to_h()` is an alias for `serializable_hash()` in the same class. It calls `attributes_hash()` and `associations_hash()`. 
https://github.com/rails-api/active_model_serializers/blob/0-10-stable/lib/active_model/serializer.rb#L357-L365
```ruby
# active_model_serializers/lib/active_model/serializer.rb
def serializable_hash(adapter_options = nil, options = {}, adapter_instance = self.class.serialization_adapter_instance)
  adapter_options ||= {}
  options[:include_directive] ||= ActiveModel::Serializer.include_directive_from_options(adapter_options)
  resource = attributes_hash(adapter_options, options, adapter_instance)
  relationships = associations_hash(adapter_options, options, adapter_instance)
  resource.merge(relationships)
end
alias to_hash serializable_hash
alias to_h serializable_hash
```

`attributes_hash()` calls `attributes()`.
https://github.com/rails-api/active_model_serializers/blob/0-10-stable/lib/active_model/serializer.rb#L386-L394
```ruby
# active_model_serializers/lib/active_model/serializer.rb
def attributes_hash(_adapter_options, options, adapter_instance)
  if self.class.cache_enabled?
    fetch_attributes(options[:fields], options[:cached_attributes] || {}, adapter_instance)
  elsif self.class.fragment_cache_enabled?
    fetch_attributes_fragment(adapter_instance, options[:cached_attributes] || {})
  else
    attributes(options[:fields], true)
  end
end
```

`attributes()` calls `ActiveModel::Serializer::Refrection#value()` of each reflection instance.
https://github.com/rails-api/active_model_serializers/blob/0-10-stable/lib/active_model/serializer.rb#L339-L352
```ruby
# active_model_serializers/lib/active_model/serializer.rb
def attributes(requested_attrs = nil, reload = false)
  @attributes = nil if reload
  @attributes ||= self.class._attributes_data.each_with_object({}) do |(key, attr), hash|
    next if attr.excluded?(self)
    next unless requested_attrs.nil? || requested_attrs.include?(key)
    hash[key] = attr.value(self) # This calls `ActiveModel::Serializer::Refrection#value()`
  end
end
```

`ActiveModel::Serializer::Refrection#value()` sets a resource instance to `@object`. **This is where the resource instance is overwritten by another thread**
https://github.com/rails-api/active_model_serializers/blob/0-10-stable/lib/active_model/serializer/reflection.rb
```ruby
# active_model_serializers/lib/active_model/serializer/reflection.rb 
def value(serializer, include_slice)
  @object = serializer.object # This line sets a resource to @object which is referred as `object` in a block which is given to `has_many` association
  @scope = serializer.scope

  block_value = instance_exec(serializer, &block) if block
  return unless include_data?(include_slice)

  if block && block_value != :nil
    block_value
  else
    serializer.read_attribute_for_serialization(name)
  end
end
```

Then `ActiveModel::Serializer#associations()`, which is called in `serializable_hash()` above, evaluates a block which is given to an association definition (e.g. `has_many :comments` in my PostSerializer). The block evaluated in reflection instance's context.
https://github.com/rails-api/active_model_serializers/blob/0-10-stable/lib/active_model/serializer.rb#L344-L349
```ruby
# active_model_serializers/lib/active_model/serializer.rb
def associations(include_directive = ActiveModelSerializers.default_include_directive, include_slice = nil)
  include_slice ||= include_directive
  return Enumerator.new {} unless object

  Enumerator.new do |y|
    self.class._reflections.each do |key, reflection|
      next if reflection.excluded?(self)
      next unless include_directive.key?(key)

      association = reflection.build_association(self, instance_options, include_slice)

      # This evaluates a block which is given to an association.
      y.yield association
    end
  end
end
```
Because of above codes, my CommentSerializer serialized wrong Comment because Post id:1 which was held by a reflection instance had been replaced with Post id:2 by the subsequent request which was processed in another thread.
