rm -rf public
hugo --theme=hyde
mv public/tachikoma-blog/post/* public/post/
rm -rf public/tachikoma-blog/