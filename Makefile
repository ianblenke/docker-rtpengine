all:
	docker-compose build
	docker-compose up --force-recreate
