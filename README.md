## Overview
Read FLAC tags from flac music file for Julia
## Installation

```julia-repl
(@v1.9) pkg> add https://github.com/xing8star/FLACMetadatas.jl
```

## Example
```julia
using FLACMetadatas
m=FLACMetadata("yourmusic.flac")
save(m)
```


