package main

import (
	"context"
	"errors"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

func main() {
	_ = godotenv.Load("../.env", ".env")

	mongoURI := strings.TrimSpace(os.Getenv("MONGODB_URI"))
	jwtSecret := os.Getenv("JWT_SECRET")
	if mongoURI == "" {
		log.Fatal("MONGODB_URI is required")
	}
	if len([]byte(jwtSecret)) < 32 {
		log.Fatal("JWT_SECRET must be at least 32 bytes")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	client, err := mongo.Connect(ctx, options.Client().ApplyURI(mongoURI).SetServerSelectionTimeout(10*time.Second))
	if err != nil {
		log.Fatalf("connect to MongoDB: %v", err)
	}
	defer func() {
		if err := client.Disconnect(context.Background()); err != nil {
			log.Printf("disconnect from MongoDB: %v", err)
		}
	}()
	if err := client.Ping(ctx, nil); err != nil {
		log.Fatalf("ping MongoDB: %v", err)
	}

	api, err := newAPI(client.Database(databaseName(mongoURI)), []byte(jwtSecret))
	if err != nil {
		log.Fatal(err)
	}
	if err := api.ensureIndexes(ctx); err != nil {
		log.Fatalf("create MongoDB indexes: %v", err)
	}

	gin.SetMode(gin.ReleaseMode)
	router := gin.New()
	router.Use(gin.Recovery(), gin.Logger())
	router.Use(corsMiddleware(strings.Split(os.Getenv("WEB_ORIGINS"), ",")))
	api.registerRoutes(router)

	listener, err := net.Listen("tcp", "127.0.0.1:3000")
	if err != nil {
		log.Fatalf("listen on 127.0.0.1:3000: %v", err)
	}
	server := &http.Server{
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	log.Printf("Motchiy ToDo API listening on http://127.0.0.1:3000")
	if err := server.Serve(listener); !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("serve API: %v", err)
	}
}

func databaseName(uri string) string {
	parsed, err := url.Parse(uri)
	if err != nil {
		return "motchiy_todo"
	}
	name := strings.Trim(parsed.Path, "/")
	if name == "" || strings.Contains(name, "@") {
		return "motchiy_todo"
	}
	return name
}
