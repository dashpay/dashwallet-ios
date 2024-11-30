CREATE TABLE username_requests (
    requestId TEXT PRIMARY KEY,
    username TEXT NOT NULL,
    createdAt INTEGER NOT NULL,
    identity TEXT NOT NULL,
    link TEXT,
    votes INTEGER NOT NULL,
    isApproved INTEGER NOT NULL
);
