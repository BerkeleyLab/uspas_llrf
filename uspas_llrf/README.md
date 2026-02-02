# LEEP CLI examples

```
pip install leep
```

* List available registers

    ```
    leep leep://192.168.19.122:803 list
    ```

* Read register

    ```
    leep leep://192.168.19.122:803 reg chan_keep
    ```

* Write register

    ```
    leep leep://192.168.19.122:803 reg chak_keep=0x3ff
    ```