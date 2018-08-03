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
