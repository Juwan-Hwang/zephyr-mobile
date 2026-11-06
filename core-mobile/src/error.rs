//! 错误类型，与 contract §10 ErrorCode 对齐。

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum MobileError {
    #[error("io: {0}")]
    Io(String),
    #[error("invalid: {0}")]
    Invalid(String),
    #[error("corrupt: {0}")]
    Corrupt(String),
    #[error("not found: {0}")]
    NotFound(String),
    #[error("rule input invalid: {0}")]
    RuleInputInvalid(String),
    #[error("subscription invalid: {0}")]
    SubscriptionInvalid(String),
}

impl From<std::io::Error> for MobileError {
    fn from(e: std::io::Error) -> Self {
        MobileError::Io(e.to_string())
    }
}
