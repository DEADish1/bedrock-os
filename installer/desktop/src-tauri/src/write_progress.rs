use serde::{Deserialize, Serialize};

pub const INSTALLER_PROGRESS_EVENT: &str = "bedrock://installer-progress";

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum WritePhase {
    Preparing,
    AwaitingApproval,
    Writing,
    Verifying,
    Finalizing,
    Complete,
    Failed,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct PipelineProgress {
    pub phase: WritePhase,
    pub completed_bytes: u64,
    pub total_bytes: u64,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub struct WriteProgress {
    pub schema: u8,
    pub session_id: String,
    pub sequence: u64,
    pub phase: WritePhase,
    pub completed_bytes: u64,
    pub total_bytes: u64,
}

impl WriteProgress {
    pub fn new(
        session_id: &str,
        sequence: u64,
        phase: WritePhase,
        completed_bytes: u64,
        total_bytes: u64,
    ) -> Result<Self, String> {
        let finished_phase = matches!(phase, WritePhase::Finalizing | WritePhase::Complete);
        if uuid::Uuid::parse_str(session_id).is_err()
            || sequence == 0
            || total_bytes == 0
            || completed_bytes > total_bytes
            || (finished_phase && completed_bytes != total_bytes)
        {
            return Err("The installer progress update is invalid.".into());
        }
        Ok(Self {
            schema: 1,
            session_id: session_id.to_string(),
            sequence,
            phase,
            completed_bytes,
            total_bytes,
        })
    }
}

pub struct ProgressTracker {
    session_id: String,
    total_bytes: u64,
    sequence: u64,
    phase: Option<WritePhase>,
    completed_bytes: u64,
}

impl ProgressTracker {
    pub fn new(session_id: &str, total_bytes: u64) -> Result<Self, String> {
        if uuid::Uuid::parse_str(session_id).is_err() || total_bytes == 0 {
            return Err("The installer progress identity is invalid.".into());
        }
        Ok(Self {
            session_id: session_id.to_string(),
            total_bytes,
            sequence: 0,
            phase: None,
            completed_bytes: 0,
        })
    }

    pub fn update(
        &mut self,
        phase: WritePhase,
        completed_bytes: u64,
    ) -> Result<WriteProgress, String> {
        let next_sequence = self
            .sequence
            .checked_add(1)
            .ok_or_else(|| "The installer progress sequence overflowed.".to_string())?;
        let update = WriteProgress::new(
            &self.session_id,
            next_sequence,
            phase,
            completed_bytes,
            self.total_bytes,
        )?;
        self.accept(update.clone())?;
        Ok(update)
    }

    pub fn accept(&mut self, update: WriteProgress) -> Result<(), String> {
        let rank = |value: WritePhase| match value {
            WritePhase::Preparing => 0,
            WritePhase::AwaitingApproval => 1,
            WritePhase::Writing => 2,
            WritePhase::Verifying => 3,
            WritePhase::Finalizing => 4,
            WritePhase::Complete | WritePhase::Failed => 5,
        };
        let expected_sequence = self
            .sequence
            .checked_add(1)
            .ok_or_else(|| "The installer progress sequence overflowed.".to_string())?;
        if update.schema != 1
            || update.session_id != self.session_id
            || update.total_bytes != self.total_bytes
            || update.sequence != expected_sequence
            || WriteProgress::new(
                &update.session_id,
                update.sequence,
                update.phase,
                update.completed_bytes,
                update.total_bytes,
            )
            .is_err()
            || self.phase == Some(WritePhase::Complete)
            || self.phase == Some(WritePhase::Failed)
            || self
                .phase
                .is_some_and(|previous| rank(update.phase) < rank(previous))
            || (self.phase == Some(update.phase)
                && update.completed_bytes < self.completed_bytes)
        {
            return Err("The installer progress sequence moved backward.".into());
        }
        self.sequence = update.sequence;
        self.phase = Some(update.phase);
        self.completed_bytes = update.completed_bytes;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::{ProgressTracker, WritePhase, WriteProgress};

    const SESSION: &str = "5d776cd0-c6b8-44d2-a8e0-8e3b56f0fb7d";

    #[test]
    fn accepts_monotonic_bounded_progress() {
        let mut tracker = ProgressTracker::new(SESSION, 100).unwrap();
        let first = tracker.update(WritePhase::Preparing, 0).unwrap();
        let second = tracker.update(WritePhase::Writing, 60).unwrap();
        let third = tracker.update(WritePhase::Verifying, 100).unwrap();
        let finalizing = tracker.update(WritePhase::Finalizing, 100).unwrap();
        let complete = tracker.update(WritePhase::Complete, 100).unwrap();
        assert_eq!((first.sequence, second.sequence, third.sequence), (1, 2, 3));
        assert_eq!(finalizing.phase, WritePhase::Finalizing);
        assert_eq!(complete.sequence, 5);
    }

    #[test]
    fn rejects_invalid_identity_bounds_and_backward_updates() {
        assert!(ProgressTracker::new("not-a-session", 100).is_err());
        assert!(WriteProgress::new(SESSION, 1, WritePhase::Writing, 101, 100).is_err());
        assert!(WriteProgress::new(SESSION, 1, WritePhase::Complete, 99, 100).is_err());
        let mut tracker = ProgressTracker::new(SESSION, 100).unwrap();
        tracker.update(WritePhase::Writing, 50).unwrap();
        assert!(tracker.update(WritePhase::Writing, 49).is_err());
        tracker.update(WritePhase::Complete, 100).unwrap();
        assert!(tracker.update(WritePhase::Failed, 100).is_err());
    }

    #[test]
    fn accepts_only_exact_remote_session_sequence_and_size() {
        let mut sender = ProgressTracker::new(SESSION, 100).unwrap();
        let update = sender.update(WritePhase::Writing, 25).unwrap();
        let encoded = serde_json::to_vec(&update).unwrap();
        let decoded: WriteProgress = serde_json::from_slice(&encoded).unwrap();
        let mut receiver = ProgressTracker::new(SESSION, 100).unwrap();
        receiver.accept(decoded.clone()).unwrap();
        assert!(receiver.accept(decoded).is_err());

        let mut wrong_session = ProgressTracker::new(
            "85ca2b97-fdf4-4773-a397-27c0e6b61aee",
            100,
        )
        .unwrap();
        assert!(wrong_session.accept(update.clone()).is_err());
        let mut wrong_size = ProgressTracker::new(SESSION, 101).unwrap();
        assert!(wrong_size.accept(update).is_err());
    }
}
