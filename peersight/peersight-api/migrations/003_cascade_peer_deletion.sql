-- Drop and recreate foreign keys referencing peers with ON DELETE CASCADE to allow deleting peers
ALTER TABLE endpoints 
    DROP CONSTRAINT IF EXISTS endpoints_peer_id_fkey,
    ADD CONSTRAINT endpoints_peer_id_fkey 
        FOREIGN KEY (peer_id) 
        REFERENCES peers(id) 
        ON DELETE CASCADE;

ALTER TABLE interfaces 
    DROP CONSTRAINT IF EXISTS interfaces_peer_id_fkey,
    ADD CONSTRAINT interfaces_peer_id_fkey 
        FOREIGN KEY (peer_id) 
        REFERENCES peers(id) 
        ON DELETE CASCADE;
