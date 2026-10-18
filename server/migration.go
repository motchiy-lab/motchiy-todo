package main

import (
	"context"
	"errors"
	"fmt"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

func migrateUserIDs(ctx context.Context, database *mongo.Database) error {
	users := database.Collection("users")
	cursor, err := users.Find(ctx, bson.M{})
	if err != nil {
		return fmt.Errorf("find users for UUID migration: %w", err)
	}
	defer cursor.Close(ctx)

	for cursor.Next(ctx) {
		var legacy struct {
			ID            primitive.ObjectID `bson:"_id"`
			EmailVerified *bool              `bson:"emailVerified"`
		}
		if err := cursor.Decode(&legacy); err != nil {
			return fmt.Errorf("decode user for UUID migration: %w", err)
		}
		oldOwners := []any{legacy.ID}
		rawUserID := cursor.Current.Lookup("userId")
		userID := ""
		switch rawUserID.Type {
		case bson.TypeString:
			value := rawUserID.StringValue()
			if validUserID(value) {
				userID = value
			} else {
				oldOwners = append(oldOwners, value)
			}
		case bson.TypeObjectID:
			if oldID := rawUserID.ObjectID(); oldID != legacy.ID {
				oldOwners = append(oldOwners, oldID)
			}
		}
		if userID == "" {
			userID, err = newUserID()
			if err != nil {
				return fmt.Errorf("generate UUID for user %s: %w", legacy.ID.Hex(), err)
			}
		}

		fields := bson.M{"userId": userID}
		if legacy.EmailVerified == nil {
			fields["emailVerified"] = false
		}
		if _, err := users.UpdateOne(ctx, bson.M{"_id": legacy.ID}, bson.M{"$set": fields}); err != nil {
			return fmt.Errorf("save UUID for user %s: %w", legacy.ID.Hex(), err)
		}
		for _, collectionName := range []string{"sessions", "tasklists", "usersettings"} {
			for _, oldOwner := range oldOwners {
				if _, err := database.Collection(collectionName).UpdateMany(ctx,
					bson.M{"userId": oldOwner},
					bson.M{"$set": bson.M{"userId": userID}},
				); err != nil {
					return fmt.Errorf("migrate %s ownership for user %s: %w", collectionName, legacy.ID.Hex(), err)
				}
			}
		}
		if legacy.EmailVerified == nil || !*legacy.EmailVerified {
			if _, err := database.Collection("sessions").UpdateMany(ctx,
				bson.M{"userId": userID, "revokedAt": nil},
				bson.M{"$set": bson.M{"revokedAt": time.Now().UTC()}},
			); err != nil {
				return fmt.Errorf("revoke unverified sessions for user %s: %w", legacy.ID.Hex(), err)
			}
		}
	}
	if err := cursor.Err(); err != nil {
		return fmt.Errorf("iterate users for UUID migration: %w", err)
	}
	if err := cursor.Close(ctx); err != nil && !errors.Is(err, context.Canceled) {
		return fmt.Errorf("close UUID migration cursor: %w", err)
	}
	return nil
}
