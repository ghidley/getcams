HPWREN Camera image processing system, currently consisting of 3 components: updateanimations (HPWREN 1.1) - legacy code for receiving and processing copies of images fetched by archive* servers run_cameras - (HPWREN 1.5) - Camera image fetch processing system to replace archive* image fetching. Runs as services on c? Reads control files and manages spawning of getcams-xxx processes for fetching images from type xxx cameras getcams-xxx - (HPWREN 1.5) - Camera fetch, processing, publishing and archival scripts (e.g. getcams-iqeye.pl for Iqeye cameras)


