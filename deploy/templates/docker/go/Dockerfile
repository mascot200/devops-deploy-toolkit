# syntax=docker/dockerfile:1
# Go service. Copy to your repo root as ./Dockerfile and adjust the lines marked ADJUST.
# Build:  docker build -t my-app:dev .      Run: docker run --rm -p 8080:8080 my-app:dev

FROM golang:1.23 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# ADJUST: the package that contains main()
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/app .

# distroless: no shell, no package manager, runs as a non-root user
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/app /app
ENV PORT=8080
EXPOSE 8080
# The app must listen on $PORT and serve GET /healthz -> 200.
ENTRYPOINT ["/app"]
