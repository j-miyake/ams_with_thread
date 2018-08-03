class Post < ApplicationRecord
  has_many :comments

  class << self
    def concurrent_serializing
      posts = {}
      t1 = Thread.new do
        posts[:first] =  PostSerializer.new(Post.first, {}).to_json
      end
      t2 = Thread.new do
        posts[:second] = PostSerializer.new(Post.second, {}).to_json
      end
      [t1, t2].map(&:join)
      pp posts
    end
  end
end
