use empucad_core::EngineError;

/// Deliberately a plain struct + C-style enum (not an enum with payloads): flutter_rust_bridge
/// generates `freezed` sealed classes for payload enums, and EmpuCAD does not use freezed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorKind {
    NotWatertight,
    InvalidInput,
    EmptyResult,
    Stl,
}

/// Thrown in Dart as an ordinary exception object.
#[derive(Debug, Clone)]
pub struct EngineApiError {
    pub kind: ErrorKind,
    pub detail: String,
}

impl EngineApiError {
    pub fn invalid(detail: impl Into<String>) -> Self {
        Self { kind: ErrorKind::InvalidInput, detail: detail.into() }
    }
}

impl From<EngineError> for EngineApiError {
    fn from(e: EngineError) -> Self {
        let (kind, detail) = match e {
            EngineError::NotWatertight(d) => (ErrorKind::NotWatertight, d),
            EngineError::InvalidInput(d) => (ErrorKind::InvalidInput, d),
            EngineError::EmptyResult => (ErrorKind::EmptyResult, "boolean produced an empty result".into()),
            EngineError::Stl(d) => (ErrorKind::Stl, d),
        };
        Self { kind, detail }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn maps_every_core_error() {
        assert_eq!(EngineApiError::from(EngineError::NotWatertight("x".into())).kind, ErrorKind::NotWatertight);
        assert_eq!(EngineApiError::from(EngineError::EmptyResult).kind, ErrorKind::EmptyResult);
        assert_eq!(EngineApiError::from(EngineError::Stl("s".into())).detail, "s");
        assert_eq!(EngineApiError::invalid("bad").kind, ErrorKind::InvalidInput);
    }
}
