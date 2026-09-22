# Notifications

This explains how notifications work in OnTrack after the unification.

## The idea

Before, each type of message did its own thing. Emails were sent from many
places. There was no single system.

Now there is one system. You send a notification once. It goes out on all the
channels the user has turned on: in-app, email, and Web Push when the deployment
has VAPID keys and the user has subscribed a browser.

## The flow

    something happens in the app
        -> you call NotificationService.notify(...)
            -> saves an in-app notification (the bell)
            -> queues an ID-only email job
            -> queues an ID-only push job
                -> Sidekiq workers reload the notification and contact providers

You only call one thing. The system handles the rest.

## How to send one

Call this from anywhere in the API code:

    NotificationService.notify(
      user: project.student,
      type: 'feedback',
      event: 'task_comment_created',
      message: "New feedback is ready for #{task_definition.name}.",
      link: "/#/projects/#{project.id}"
    )

- user: who gets it.
- type: the category. One of task, feedback, portfolio, extension, general.
  This is what the user's on/off setting controls.
- event: the specific thing that happened, as a lower_snake_case string.
  Required. Use one event name per ticket, and use the same name every time you
  raise that notification, so a notification can always be traced back to the
  code that sent it.
- message: the text the user sees. Keep it short, 500 characters at most.
- link: where clicking it should take them. Optional.

type and event are different on purpose. type is the coarse category the user
switches off in their profile. event is the fine-grained reason, and there will
be many events inside one type.

## Types and preferences

Each user already has three on/off settings in their profile:

- receive_task_notifications
- receive_feedback_notifications
- receive_portfolio_notifications

The type you pass maps to one of these settings.

- task uses receive_task_notifications
- feedback uses receive_feedback_notifications
- portfolio uses receive_portfolio_notifications
- extension and general are always sent

If the matching setting is off, nothing is sent. Not the bell, not the email,
not the push. One switch controls all channels. This keeps it simple. We can add
per-channel switches later if we want.

## The pieces

- app/models/notification.rb: the notification record. Has the type, message,
  link, and whether it has been read.
- app/services/notification_service.rb: the one entry point. Checks the setting,
  saves the record, and queues the email and push channel jobs.
- app/sidekiq/notification_email_job.rb: reloads a notification by id and sends
  its email on the `mailers` queue.
- app/sidekiq/push_notification_delivery_job.rb: reloads a notification by id
  and hands it to the Web Push delivery channel on the `notifications` queue.
- app/services/push_notification_service.rb: the Web Push delivery channel. It
  remains a safe no-op until both VAPID keys are configured.
- app/mailers/notifications_mailer.rb: the email. New method single_notification
  with templates in app/views/notifications_mailer.
- app/api/notifications_api.rb: the endpoints the web app calls.
- app/api/entities/notification_entity.rb: the shape of the data sent back.

## The endpoints

    GET    /api/notifications                 list my notifications
    GET    /api/notifications/unread_count     how many I have not read
    PUT    /api/notifications/:id/read         mark one as read
    PUT    /api/notifications/read_all          mark all as read
    DELETE /api/notifications/:id              delete one

    GET    /api/push_subscriptions              list my browser subscriptions
    POST   /api/push_subscriptions              register or update a browser
    DELETE /api/push_subscriptions              remove the browser identified by endpoint

Every endpoint only ever touches the current user's own notifications.

## What is on now

- In-app: working. The record is saved and the endpoints return it.
- Email: working. Best effort. If email fails, the in-app notification is still
  saved.
- Push: implemented and deliberately configuration-gated. It sends only when
  VAPID keys are set and that user has opted in from a supported browser. Keep
  the production keys blank until browser/device acceptance testing is complete.
