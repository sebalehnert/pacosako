use sqlx::{pool::PoolConnection, Sqlite};

use crate::{sync_match::SyncronizedMatch, timer::Timer};

pub type Conn = PoolConnection<Sqlite>;

// Database representation of a sync_match::SyncronizedMatch
// We don't fully normalize the data, instead we just dump JSON into the db.
pub struct RawGame {
    pub id: i64,
    pub action_history: String,
    pub timer: Option<String>,
}

/// Helper trait for simple DB storage. You would do:
///
/// impl StoreAs<RawGame> for SyncronizedMatch { .. }
pub trait StoreAs<T>: Sized {
    fn store(&self) -> Result<T, anyhow::Error>;
    fn load(stored: &T) -> Result<Self, anyhow::Error>;
}

impl StoreAs<RawGame> for SyncronizedMatch {
    fn store(&self) -> Result<RawGame, anyhow::Error> {
        let timer = if let Some(ref timer) = self.timer {
            Some(serde_json::to_string(timer)?)
        } else {
            None
        };

        Ok(RawGame {
            id: self.key.parse()?,
            action_history: serde_json::to_string(&self.actions)?,
            timer,
        })
    }

    fn load(stored: &RawGame) -> Result<Self, anyhow::Error> {
        let timer = if let Some(ref timer) = stored.timer {
            Some(serde_json::from_str(timer)?)
        } else {
            None
        };

        Ok(SyncronizedMatch {
            key: format!("{}", stored.id),
            actions: serde_json::from_str(&stored.action_history)?,
            timer,
        })
    }
}

impl RawGame {
    /// Reads a RawGame from the database given a known id.
    pub async fn select(id: i64, conn: &mut Conn) -> Result<Option<Self>, sqlx::Error> {
        sqlx::query_as!(
            RawGame,
            "select id, action_history, timer from game where id = ?",
            id
        )
        .fetch_optional(conn)
        .await
    }

    /// Writes a RawGame to the database into a new record and overrides the id.
    pub async fn insert(&mut self, conn: &mut Conn) -> Result<&mut Self, sqlx::Error> {
        self.id = sqlx::query!(
            "insert into game (action_history, timer) values (?, ?)",
            self.action_history,
            self.timer
        )
        .execute(conn)
        .await?
        .last_insert_rowid();

        Ok(self)
    }

    pub async fn update(&self, conn: &mut Conn) -> Result<(), sqlx::Error> {
        sqlx::query!(
            r"update game 
            set action_history = ?, timer = ?
            where id = ?",
            self.action_history,
            self.timer,
            self.id
        )
        .execute(conn)
        .await?;

        Ok(())
    }

    pub async fn latest(conn: &mut Conn) -> Result<Vec<Self>, sqlx::Error> {
        sqlx::query_as!(
            RawGame,
            r"select id, action_history, timer from game 
            order by created desc 
            limit 5"
        )
        .fetch_all(conn)
        .await
    }
}
