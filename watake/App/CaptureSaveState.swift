/// Pure review-retention rule. Capture UI clears pages only after metadata and
/// assets commit successfully, so save failures leave a retryable review.
enum CaptureSaveState {
    static func pagesAfterSave<Page>(_ pages: [Page], succeeded: Bool) -> [Page] {
        succeeded ? [] : pages
    }
}
