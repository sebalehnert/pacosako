use rand::{thread_rng, Rng};
use std::collections::{HashMap, HashSet};
use std::{
    borrow::Cow,
    sync::{Arc, Mutex},
};
use ws::Sender;

/// The instance manager makes sure you can have multiple instances of a thing
/// in a websocket service. This class will take care of message passing and
/// session management.
///
/// When we eventually add persistence to the instances, this will also be the
/// responsibility of the instance manager.

/// An instance is the type managed by the instance manager.
pub trait Instance: Sized {
    /// The type of messages send by the client to the server.
    type ClientMessage: ClientMessage;
    type ServerMessage: ServerMessage;
    /// The unique key used to identify the instance.
    fn key(&self) -> Cow<String>;
    /// Create a new instance and make it store the key.
    fn new_with_key(key: &str) -> Self;
    /// Accept a client message and possibly send messages back.
    fn handle_message(&mut self, message: Self::ClientMessage, ctx: &mut Context<Self>);
}

pub trait ProvidesKey {
    /// The unique key used to identify the instance.
    fn key(&self) -> Cow<String>;
}

pub trait ClientMessage: ProvidesKey + Clone {
    /// Create a client messsage that represents a client subscribing.
    fn subscribe(key: String) -> Self;
}

pub trait ServerMessage: Into<ws::Message> + Clone {
    /// Allows us to send messages to the client without knowing about the
    /// server message type in detail.
    fn error(message: Cow<String>) -> Self;
}

/// Represents the client which send a message to the game. You can send server
/// messages back to the client. The messages will be buffered and send out
/// later. This means technical error handling can be hidden from the business
/// logic.
/// The context gives the ability to broadcast messages to all clients that are
/// connected to the
pub struct Context<T: Instance> {
    reply_queue: Vec<T::ServerMessage>,
    broadcast_queue: Vec<T::ServerMessage>,
}

impl<T: Instance> Context<T> {
    pub fn reply(&mut self, message: T::ServerMessage) {
        self.reply_queue.push(message)
    }
    pub fn broadcast(&mut self, message: T::ServerMessage) {
        self.broadcast_queue.push(message)
    }
    fn new() -> Self {
        Context {
            reply_queue: vec![],
            broadcast_queue: vec![],
        }
    }
}

/// As an implementation detail for now, we lock the Manager on every access.
/// This is of course not a good implementation and we should switch over to
/// some kind of concurrent hashmap in the future.
pub struct Manager<T: Instance>(Arc<Mutex<SyncManager<T>>>);

/// Inner Manager, locked before access.
struct SyncManager<T: Instance> {
    instances: HashMap<String, InstanceMetadata<T>>,
    clients: HashMap<Sender, ClientData>,
}

struct ClientData {
    connected_to: HashSet<String>,
}

impl ClientData {
    fn new() -> Self {
        ClientData {
            connected_to: HashSet::new(),
        }
    }
}

struct InstanceMetadata<T: Instance> {
    instance: T,
    clients: HashSet<Sender>,
}

impl<T: Instance> InstanceMetadata<T> {
    fn new(instance: T) -> Self {
        InstanceMetadata {
            instance,
            clients: HashSet::new(),
        }
    }
}

/// This can't be a function because a function would have its own stack frame
/// and would need to drop the result of server.lock() before returning. This
/// is impossible if it wants to return a mutable reference to the droped data.
///
///     lock!(server: WebsocketServer) -> &mut SyncServer
macro_rules! lock {
    ( $server:expr ) => {{
        &mut *($server.0.lock().unwrap())
    }};
}

impl<T: Instance> Manager<T> {
    /// Creates an empty manager that does not contain any games yet.
    pub fn new() -> Self {
        Manager(Arc::from(Mutex::from(SyncManager::new())))
    }
    /// Creates a new instance and returns its key.
    pub fn new_instance(&self) -> String {
        lock!(self).new_instance()
    }
    /// Routes a message to the corresponding instance
    pub fn handle_message(&self, message: T::ClientMessage, sender: Sender) {
        lock!(self).handle_message(message, sender)
    }
    /// Subscribes a sender to the instance with the given key.
    pub fn subscribe(&self, key: Cow<String>, sender: Sender) {
        lock!(self).subscribe(key, sender)
    }
}

impl<T: Instance> SyncManager<T> {
    /// Creates an empty manager that does not contain any games yet.
    pub fn new() -> Self {
        SyncManager {
            instances: HashMap::new(),
            clients: HashMap::new(),
        }
    }

    fn new_instance(&mut self) -> String {
        let key = generate_unique_key(&self.instances);

        let new_instance = T::new_with_key(&key);
        self.instances
            .insert(key.clone(), InstanceMetadata::new(new_instance));

        key
    }

    fn handle_message(&mut self, message: T::ClientMessage, sender: Sender) {
        let key = message.key();
        if let Some(instance) = self.instances.get_mut(&*key) {
            Self::handle_message_for_instance(message, &sender, instance)
        } else {
            Self::send_message(&sender, Self::error_no_instance(key));
        }
    }

    fn handle_message_for_instance(
        message: T::ClientMessage,
        sender: &Sender,
        instance: &mut InstanceMetadata<T>,
    ) {
        let mut context = Context::new();
        instance.instance.handle_message(message, &mut context);

        // Send messages back to client
        for msg in context.reply_queue {
            Self::send_message(sender, msg);
        }

        // Broadcast messages to all connected clients
        for msg in context.broadcast_queue {
            for client in &instance.clients {
                Self::send_message(client, msg.clone());
            }
        }
    }

    fn send_message(sender: &Sender, message: T::ServerMessage) {
        match sender.send(message) {
            Ok(()) => { /* Nothing to do, we are happy. */ }
            Err(_) => todo!("handle ws send errors"),
        }
    }

    fn subscribe(&mut self, key: Cow<String>, sender: Sender) {
        // Check if an instance with this key exists
        if let Some(instance) = self.instances.get_mut(&*key) {
            let mut client_already_connected = false;

            // Check if we already track this client
            let client = self.clients.get_mut(&sender);
            if let Some(client) = client {
                // If the set did have this value present, false is returned.
                client_already_connected = !client.connected_to.insert(key.clone().into_owned());
            } else {
                let mut client = ClientData::new();
                client.connected_to.insert(key.clone().into_owned());
                self.clients.insert(sender.clone(), client);
            }

            if client_already_connected {
                Self::send_message(
                    &sender,
                    T::ServerMessage::error(Cow::Owned(format!(
                        "Client is already connected to {}.",
                        key
                    ))),
                );
            } else {
                instance.clients.insert(sender.clone());
                Self::handle_message_for_instance(
                    T::ClientMessage::subscribe(key.into_owned()),
                    &sender,
                    instance,
                );
            }
        } else {
            Self::send_message(&sender, Self::error_no_instance(key));
        }
    }

    /// Creates the error that is send to the client of they try to interact
    /// with an instance that does not exist.
    fn error_no_instance(key: Cow<String>) -> T::ServerMessage {
        T::ServerMessage::error(Cow::Owned(format!(
            "There is no instance with key {}.",
            key
        )))
    }
}

/// Returns a key that is not yet used in the map.
pub fn generate_unique_key<T>(map: &HashMap<String, T>) -> String {
    let rand_string = generate_key();
    if map.contains_key(&rand_string) {
        generate_unique_key(map)
    } else {
        rand_string
    }
}

fn generate_key() -> String {
    let code: usize = thread_rng().gen_range(0, 9000);
    format!("{}", code + 1000)
}

/// So I am not sure what to do about senders :-/
/// For testability, I need to be able to mock ws::Sender objects. So instead
/// of working with plain sender objects, I wrap them using a trait and can
/// then replace them with a MockSender for testing.

#[cfg(test)]
mod test {
    use super::*;

    /// This intstance manager is pretty tricky to get right, so I define a
    /// simple test instance type to test it.
    /// We need to implement all message types for this as well as an Instance
    /// stucture, so the setup is rather involved.
    /// Each instance is simply a i64 number that you can get or set by sending
    /// a message. Setting the value will broadcast to all other subscribers.

    struct TestInstance {
        key: String,
        value: i64,
    }

    #[derive(Clone)]
    enum TestClientMsg {
        Set { key: String, value: i64 },
        Get { key: String },
    }

    impl ProvidesKey for TestClientMsg {
        fn key(&self) -> Cow<String> {
            match self {
                TestClientMsg::Set { key, .. } => Cow::Borrowed(key),
                TestClientMsg::Get { key } => Cow::Borrowed(key),
            }
        }
    }

    impl ClientMessage for TestClientMsg {
        fn subscribe(key: String) -> Self {
            TestClientMsg::Get { key }
        }
    }

    #[derive(Clone)]
    enum TestServerMsg {
        IsNow { key: String, value: i64 },
        Oups { error: String },
    }

    impl From<TestServerMsg> for ws::Message {
        fn from(msg: TestServerMsg) -> Self {
            match msg {
                TestServerMsg::IsNow { key, value } => Self::text(format!("{}: {}", key, value)),
                TestServerMsg::Oups { error } => Self::text(error),
            }
        }
    }

    impl ServerMessage for TestServerMsg {
        fn error(message: Cow<String>) -> Self {
            TestServerMsg::Oups {
                error: message.into_owned(),
            }
        }
    }

    impl Instance for TestInstance {
        type ClientMessage = TestClientMsg;
        type ServerMessage = TestServerMsg;
        fn key(&self) -> Cow<String> {
            Cow::Borrowed(&self.key)
        }
        fn new_with_key(key: &str) -> Self {
            TestInstance {
                key: key.to_owned(),
                value: 0,
            }
        }
        fn handle_message(&mut self, message: Self::ClientMessage, ctx: &mut Context<Self>) {
            match message {
                TestClientMsg::Set { key, value, .. } => {
                    self.value = value;
                    ctx.broadcast(TestServerMsg::IsNow { key, value });
                }
                TestClientMsg::Get { key } => {
                    ctx.reply(TestServerMsg::IsNow {
                        key,
                        value: self.value,
                    });
                }
            }
        }
    }

    #[allow(deprecated)]
    fn new_mock_sender(id: u32) -> (Sender, impl FnMut() -> String) {
        // Yes, this is deprecated. But ws is using it, so I need it for testing.
        let (sender, receiver) = mio::channel::sync_channel(100);

        // This constructor is #[doc(hidden)], but still public.
        let sender = Sender::new(mio::Token(id as usize), sender, id);

        // The type ws::..::Command is private, so I can't talk about it and I am
        // unable to return any parameters which have this in its type parameter.
        let f = move || format!("{:?}", receiver.try_recv());

        (sender, Box::new(f))
    }

    /// Tries to connect to an instance that does not exist and fails.
    #[test]
    fn test_subscription_to_non_existing_game_fails() {
        let m = Manager::<TestInstance>::new();
        let (s1, mut r1) = new_mock_sender(1);

        m.subscribe(Cow::Owned("Game1".to_owned()), s1);

        // We expect that there is exacty one message in the replies and that
        // it is about Game1 not existing.
        assert!(r1().contains("There is no instance with key Game1."));
        assert!(r1().starts_with("Err("));
    }

    /// Creates an instance and connects to it.
    /// Tests that we recieve the state as a response.
    /// Also checks that connecting twice does work.
    #[test]
    fn test_subscription_works() {
        let m = Manager::<TestInstance>::new();
        let (s1, mut r1) = new_mock_sender(1);

        // Set up instance and connect.
        let key = m.new_instance();
        m.subscribe(Cow::Owned(key.clone()), s1.clone());

        assert!(r1().contains(&format!("{}: {}", key, 0)));
        assert_eq!(r1(), "Err(Empty)");

        m.subscribe(Cow::Owned(key.clone()), s1);

        assert!(r1().contains(&format!("Client is already connected to {}.", key)));
        assert_eq!(r1(), "Err(Empty)");

        // Check that we are still only connected once.
        assert_eq!(lock!(m).clients.len(), 1);
    }

    /// Checks that Set and Get messages are handled correctly.
    #[test]
    fn test_reply_to_get() {
        // Set up instance and connect.
        let m = Manager::<TestInstance>::new();
        let (s1, mut r1) = new_mock_sender(1);
        let key = m.new_instance();
        m.subscribe(Cow::Owned(key.clone()), s1.clone());

        // Clean channel.
        assert!(r1().contains(&format!("{}: {}", key.clone(), 0)));
        assert_eq!(r1(), "Err(Empty)");

        m.handle_message(
            TestClientMsg::Set {
                key: key.clone(),
                value: 42,
            },
            s1.clone(),
        );

        assert!(r1().contains(&format!("{}: {}", key.clone(), 42)));
        assert_eq!(r1(), "Err(Empty)");

        m.handle_message(TestClientMsg::Get { key: key.clone() }, s1.clone());

        assert!(r1().contains(&format!("{}: {}", key.clone(), 42)));
        assert_eq!(r1(), "Err(Empty)");
    }

    /// Connect two clients and check that messages get passed as expected.
    #[test]
    fn test_message_passing() {
        // Set up instance and connect.
        let m = Manager::<TestInstance>::new();
        let (s1, mut r1) = new_mock_sender(1);
        let (s2, mut r2) = new_mock_sender(2);
        let key = m.new_instance();
        m.subscribe(Cow::Owned(key.clone()), s1.clone());
        m.subscribe(Cow::Owned(key.clone()), s2.clone());

        // Clean channels
        assert!(r1().contains(&format!("{}: {}", key.clone(), 0)));
        assert_eq!(r1(), "Err(Empty)");
        assert!(r2().contains(&format!("{}: {}", key.clone(), 0)));
        assert_eq!(r2(), "Err(Empty)");

        // Update the value from client 1 and check that it arrives in client 2.
        m.handle_message(
            TestClientMsg::Set {
                key: key.clone(),
                value: 42,
            },
            s1.clone(),
        );

        assert!(r2().contains(&format!("{}: {}", key.clone(), 42)));
        assert_eq!(r2(), "Err(Empty)");
    }
}