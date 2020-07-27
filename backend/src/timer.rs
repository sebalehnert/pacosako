use chrono::{DateTime, Duration, Utc};
use pacosako::PlayerColor;
use serde::Serialize;
use std::convert::From;

/// The timer module should encapsulate the game timer state. It is importing
/// pacosako in order to work with the player colors. Otherwise it is not
/// specific to Paco Ŝako.

#[derive(Clone, Serialize)]
pub struct TimerConfig {
    #[serde(serialize_with = "serialize_seconds")]
    time_budget_white: Duration,
    #[serde(serialize_with = "serialize_seconds")]
    time_budget_black: Duration,
}

#[derive(Serialize)]
pub struct Timer {
    last_timestamp: DateTime<Utc>,
    #[serde(serialize_with = "serialize_seconds")]
    time_left_white: Duration,
    #[serde(serialize_with = "serialize_seconds")]
    time_left_black: Duration,
    timer_state: TimerState,
    config: TimerConfig,
}

/// There is no default implementation for serde::Serialize for Duration, so we
/// have to provide it ourself. This also gives us the flexibility to decide
/// how much precision we expose to the client.
fn serialize_seconds<S: serde::Serializer>(duration: &Duration, s: S) -> Result<S::Ok, S::Error> {
    s.serialize_f32(duration.num_milliseconds() as f32 / 1000f32)
}

impl Timer {
    // Start a timer. This does nothing when the Timer is alread running or already timed out.
    pub fn start(&mut self, start_time: DateTime<Utc>) {
        if self.timer_state == TimerState::Paused {
            self.last_timestamp = start_time;
            self.timer_state = TimerState::Running;
        }
    }

    pub fn use_time(&mut self, player: PlayerColor, now: DateTime<Utc>) -> TimerState {
        if self.timer_state != TimerState::Running {
            return self.timer_state;
        }

        let time_passed: Duration = now - self.last_timestamp;

        let time_left = match player {
            PlayerColor::White => {
                self.time_left_white = self.time_left_white - time_passed;
                self.time_left_white
            }
            PlayerColor::Black => {
                self.time_left_black = self.time_left_black - time_passed;
                self.time_left_black
            }
        };

        self.last_timestamp = now;

        // Check if the time ran out
        if time_left <= Duration::nanoseconds(0) {
            self.timer_state = TimerState::Timeout(player);
        }

        self.timer_state
    }
}

/// Gives the current state of the timer. When the timer is running it does
/// not know which player is currently controlling it. The time will be reduced
/// when an action is send to the server.
#[derive(Debug, PartialEq, Eq, Copy, Clone, Serialize)]
pub enum TimerState {
    Paused,
    Running,
    Timeout(PlayerColor),
}

impl From<TimerConfig> for Timer {
    fn from(config: TimerConfig) -> Self {
        Timer {
            last_timestamp: Utc::now(),
            time_left_white: config.time_budget_white.clone(),
            time_left_black: config.time_budget_black.clone(),
            timer_state: TimerState::Paused,
            config,
        }
    }
}

#[cfg(test)]
mod test {
    use super::*;

    fn test_timer_config() -> TimerConfig {
        TimerConfig {
            time_budget_white: Duration::seconds(5 * 60),
            time_budget_black: Duration::seconds(4 * 60),
        }
    }

    #[test]
    fn create_timer_from_config() {
        let config: TimerConfig = test_timer_config();
        let timer: Timer = config.into();
        assert_eq!(timer.timer_state, TimerState::Paused);
        assert_eq!(timer.time_left_white, Duration::seconds(300));
        assert_eq!(timer.time_left_black, Duration::seconds(240));
    }

    #[test]
    fn test_start_timer() {
        let mut timer: Timer = test_timer_config().into();
        let now = Utc::now();

        timer.start(now);
        assert_eq!(timer.last_timestamp, now);
        assert_eq!(timer.timer_state, TimerState::Running);

        let now2 = now + Duration::seconds(3);
        timer.start(now2);
        assert_eq!(timer.last_timestamp, now);
        assert_eq!(timer.timer_state, TimerState::Running);
    }

    #[test]
    fn test_use_time() {
        use PlayerColor::*;

        let mut timer: Timer = test_timer_config().into();
        let now = Utc::now();

        // Using time does not work when the timer is not running
        let unused_future = now + Duration::seconds(100);
        timer.use_time(White, unused_future);
        assert_eq!(timer.time_left_white, Duration::seconds(300));
        assert_eq!(timer.time_left_black, Duration::seconds(240));

        timer.start(now);

        // Use 15 seconds from the white player
        let now = now + Duration::seconds(15);
        timer.use_time(White, now);
        assert_eq!(timer.time_left_white, Duration::seconds(285));
        assert_eq!(timer.time_left_black, Duration::seconds(240));
        assert_eq!(timer.timer_state, TimerState::Running);

        // Use 7 seconds from the black player
        let now = now + Duration::seconds(7);
        timer.use_time(Black, now);
        assert_eq!(timer.time_left_white, Duration::seconds(285));
        assert_eq!(timer.time_left_black, Duration::seconds(233));
        assert_eq!(timer.timer_state, TimerState::Running);

        // Use 8 seconds from the white player
        let now = now + Duration::seconds(8);
        timer.use_time(White, now);
        assert_eq!(timer.time_left_white, Duration::seconds(277));
        assert_eq!(timer.time_left_black, Duration::seconds(233));
        assert_eq!(timer.timer_state, TimerState::Running);

        // Use 500 seconds from the black player, this should yield a timeout.
        let now = now + Duration::seconds(500);
        timer.use_time(Black, now);
        assert_eq!(timer.time_left_white, Duration::seconds(277));
        assert_eq!(timer.time_left_black, Duration::seconds(-267));
        assert_eq!(timer.timer_state, TimerState::Timeout(Black));
    }
}
