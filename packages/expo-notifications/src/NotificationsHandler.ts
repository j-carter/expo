import { EventEmitter, Subscription, CodedError } from '@unimodules/core';
import NotificationsHandlerModule, { NotificationBehavior } from './NotificationsHandlerModule';

type Notification = any;

export class NotificationTimeoutError extends CodedError {
  info: { notification: Notification; id: string };
  constructor(notificationId: string, notification: Notification) {
    super('ERR_NOTIFICATION_TIMEOUT', `Notification handling timed out for ID ${notificationId}.`);
    this.info = { id: notificationId, notification };
  }
}

export type NotificationHandlingError = NotificationTimeoutError | Error;

export interface NotificationDelegate {
  handleNotification: (notification: Notification) => Promise<NotificationBehavior>;
  handleSuccess?: (notificationId: string) => void;
  handleError?: (error: NotificationHandlingError) => void;
}

type HandleNotificationEvent = {
  id: string;
  notification: Notification;
};

type HandleNotificationTimeoutEvent = HandleNotificationEvent;

// Web uses SyntheticEventEmitter
const notificationEmitter = new EventEmitter(NotificationsHandlerModule);

const handleNotificationEventName = 'onHandleNotification';
const handleNotificationTimeoutEventName = 'onHandleNotificationTimeout';

let handleSubscription: Subscription | null = null;
let handleTimeoutSubscription: Subscription | null = null;

export function setNotificationDelegate(delegate: NotificationDelegate): void {
  if (handleSubscription) {
    handleSubscription.remove();
    handleSubscription = null;
  }
  if (handleTimeoutSubscription) {
    handleTimeoutSubscription.remove();
    handleTimeoutSubscription = null;
  }

  handleSubscription = notificationEmitter.addListener<HandleNotificationEvent>(
    handleNotificationEventName,
    async ({ id, notification }) => {
      try {
        const requestedBehavior = await delegate.handleNotification(notification);
        await NotificationsHandlerModule.handleNotificationAsync(id, requestedBehavior);
        // TODO: Remove eslint-disable once we upgrade to a version that supports ?. notation.
        // eslint-disable-next-line
        delegate.handleSuccess?.(id);
      } catch (error) {
        // TODO: Remove eslint-disable once we upgrade to a version that supports ?. notation.
        // eslint-disable-next-line
        delegate.handleError?.(error);
      }
    }
  );

  handleTimeoutSubscription = notificationEmitter.addListener<HandleNotificationTimeoutEvent>(
    handleNotificationTimeoutEventName,
    ({ id, notification }) => delegate.handleError?.(new NotificationTimeoutError(id, notification))
  );
}
