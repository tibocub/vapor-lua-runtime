local vlr = require("vlr")
-- fd readiness: stdin is /dev/null under the runner, which is always readable
local fd, err = vlr.wait_fd(0, 1)
assert(fd == 0, tostring(err))
