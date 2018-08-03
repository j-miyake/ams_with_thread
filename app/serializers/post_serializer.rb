class PostSerializer < ActiveModel::Serializer
  attributes :id, :title, :body
  has_many :comments, serializer: CommentSerializer do
    sleep 3
    object.comments
  end
end
