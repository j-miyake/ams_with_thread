# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

post1 = Post.create title: "post1", body: "This is post1!"
post2 = Post.create title: "post2", body: "This is post2!"

Comment.create body: "This is a comment of post1", post: post1
Comment.create body: "This is a comment of post2", post: post2
