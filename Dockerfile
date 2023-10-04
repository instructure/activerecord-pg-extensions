FROM ruby:3.1

RUN apt update && \
	apt install -y --no-install-recommends \
		pipx \
		postgresql-client && \
	rm -rf /var/lib/apt/lists/* && \
	pipx install pre-commit && \
	gem update --system

WORKDIR /app
ENV PATH="/app/bin:${PATH}"
