run:
	docker run \
		--network=host \
		--env-file=.env \
		-v meat-my-beat-i_data:/srv/root/.data \
		-it bakenohana:latest

build:
	DOCKER_BUILDKIT=1 docker build -t bakenohana:latest .
