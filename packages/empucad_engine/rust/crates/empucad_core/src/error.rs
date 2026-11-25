use thiserror::Error;

#[derive(Debug, Error)]
pub enum EngineError {
    #[error("mesh is not a closed, watertight solid: {0}")]
    NotWatertight(String),
    #[error("invalid input: {0}")]
    InvalidInput(String),
    #[error("boolean operation produced an empty result")]
    EmptyResult,
    #[error("STL parse error: {0}")]
    Stl(String),
}

pub type Result<T> = std::result::Result<T, EngineError>;
