-- What this step does. Safe to copy — no live secrets appear here.
-- Run as an ADB administrator. This creates an ordinary Oracle role,
-- not a Deep Data Security data role.

-- 1. Create a plain role that grants nothing but the ability to connect.
CREATE ROLE APP_LOCAL_CONNECT;
GRANT CREATE SESSION TO APP_LOCAL_CONNECT;

-- Nothing here touches Deep Data Security. A later page attaches this
-- same role to the data roles once they exist.
