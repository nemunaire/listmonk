FROM node:lts-alpine AS frontend-builder
RUN apk --no-cache add make grep
COPY frontend frontend/
COPY Makefile VERSION ./
RUN make build-frontend

FROM golang:alpine AS backend-builder
RUN apk --no-cache add make grep
WORKDIR /go/listmonk
COPY . .
COPY --from=frontend-builder frontend/dist frontend/dist/
RUN sed -i 's/pack-bin: build-frontend/pack-bin:/' Makefile && \
    make pack-bin

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /listmonk
COPY --from=backend-builder /go/listmonk/listmonk .
COPY config.toml.sample config.toml
COPY config-demo.toml .
CMD ["./listmonk"]
EXPOSE 9000
