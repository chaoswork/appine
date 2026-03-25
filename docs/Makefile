
all: usage.html

usage.html: usage.md template.html
	pandoc usage.md -o usage.html --template template.html --standalone
