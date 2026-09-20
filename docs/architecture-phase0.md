# Phase 0 Logical Architecture

```text
                         MEDIA BANK
                             |
                         MEDIA ENGINE
                             |
               +-------------+-------------+
               |                           |
          ENDPOINTS B                   ENDPOINTS A
   (remote/CWP/radio/phone)            (tested CWPs)
               |                           |
               +------ SIP/RTP/RTCP -------+
                           |
                    operational core
                           |
          +----------------+----------------+
          |                                 |
      CWP recording                    service recording
       RTSP/RTP                        via Gateway
          |                                 |
          +----------------+----------------+
                           |
                        RECORDER
                           |
                 MXF + SQLite + metrics
                           |
                Player / Export / Report
```

Independent witness:
`dumpcap/Wireshark -> PCAPNG`

External-recorder mode replaces the PoC recorder target with an authorized physical recorder endpoint using a profile file; source code is unchanged.
