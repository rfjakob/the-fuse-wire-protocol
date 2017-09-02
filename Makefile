index.html: README.md
	pandoc -s README.md --css style.css -o index.html

.PHONY: clean
clean:
	rm -f index.html