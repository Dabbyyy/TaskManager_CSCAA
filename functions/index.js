const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp();

/**
 * Triggered every time a new document is added to the `notifications` collection.
 * Looks up the recipient user's FCM token from Firestore and sends a real
 * FCM push notification so the alert arrives even when the app is fully closed.
 */
exports.sendNotificationOnCreate = onDocumentCreated(
  "notifications/{docId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) {
      console.log("No data in notification document.");
      return;
    }

    const toEmail = data.to;
    const title = data.title || "CSCAA TaskFlow";
    const body = data.body || "You have a new task update.";

    if (!toEmail) {
      console.log("No recipient email found.");
      return;
    }

    // Look up the FCM token from the user's Firestore doc
    const db = getFirestore();
    const userDoc = await db.collection("users").doc(toEmail).get();

    if (!userDoc.exists) {
      console.log(`User doc not found for: ${toEmail}`);
      return;
    }

    const fcmToken = userDoc.data()?.fcmToken;
    if (!fcmToken) {
      console.log(`No FCM token for user: ${toEmail}`);
      return;
    }

    // Build and send the FCM message
    const message = {
      token: fcmToken,
      notification: {
        title: title,
        body: body,
      },
      data: {
        title: title,
        body: body,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        priority: "high",
        notification: {
          channelId: "cscaa_main_channel",
          notificationPriority: "PRIORITY_MAX",
          defaultSound: true,
          defaultVibrateTimings: true,
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
      },
      apns: {
        payload: {
          aps: {
            alert: {
              title: title,
              body: body,
            },
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    try {
      const response = await getMessaging().send(message);
      console.log(`FCM sent successfully to ${toEmail}:`, response);
    } catch (err) {
      console.error(`Error sending FCM to ${toEmail}:`, err);
    }
  }
);
