# Discovery

As you may have seen in [the introduction](./introduction.md), FastAI.jl makes it possible to train models in just 5 lines of code. However, if you have a task in mind, you need to know what datasets you can train on and if there are convenience learning method constructors. For example, the introduction loads the `"imagenette2-160"` dataset and uses [`ImageClassificationSingle`](#) to construct a learning method. Now what if, instead of classifying an image into one class, we want to classify every single pixel into a class (semantic segmentation)? Now we need a dataset with pixel-level annotations and a learning method that can process those segmentation masks.

For finding both, we can make use of `Block`s. A `Block` represents a kind of data, for example images, labels or keypoints. For supervised learning tasks, we have an input block and a target block. If we wanted to classify whether 2D images contain a cat or a dog, we could use the blocks `(Image{2}(), Label(["cat", "dog"]))`, while for semantic segmentation, we'll have an input `Image` block and a target [`Mask`](#) block.

## Finding a dataset

To find a dataset with compatible samples, we can pass the types of these blocks to [`finddatasets`](#) which will return a list of dataset names and recipes to load them in a suitable way.

{cell=main}
```julia
using FastAI
finddatasets(blocks=(Image, Mask))
```

We can see that the `"camvid_tiny"` dataset can be loaded so that each sample is a pair of an image and a segmentation mask. Let's use [`loaddataset`](#) to load a [data container](data_containers.md) and concrete blocks.

{cell=main}
```julia
data, blocks = loaddataset("camvid_tiny", (Image, Mask))
```

As with every data container, we can load a sample using `getobs` which gives us a tuple of an image and a segmentation mask.

{cell=main}
```julia
image, mask = sample = getobs(data, 1)
size.(sample), eltype.(sample)
```

`loaddataset` also returned `blocks` which are the concrete `Block` instances for the dataset. We passed in _types_ of blocks (`(Image, Mask)`) and get back _instances_ since the specifics of some blocks depend on the dataset. For example, the returned target block carries the labels for every class that a pixel can belong to.

{cell=main}
```julia
inputblock, targetblock = blocks
targetblock
```

With these `blocks`, we can also validate a sample of data using [`checkblock`](#) which is useful as a sanity check when using custom data containers.

{cell=main}
```julia
checkblock((inputblock, targetblock), (image, mask))
```

### Summary

In short, if you have a learning task in mind and want to load a dataset for that task, then

1. define the types of input and target block, e.g. `blocktypes = (Image, Label)`,
2. use [`finddatasets`](#)`(blocks=blocktypes)` to find compatbile datasets; and
3. run [`loaddataset`](#)`(datasetname, blocktypes)` to load a data container and the concrete blocks

### Exercises

1. Find and load a dataset for multi-label image classification. (Hint: the block for multi-category outputs is called `LabelMulti`).
2. List all datasets with `Image` as input block and any target block. (Hint: the supertype of all types is `Any`)


## Finding a learning method

Armed with a dataset, we can go to the next step: creating a learning method. Since we already have blocks defined, this amounts to defining the encodings that are applied to the data before it is used in training. Here, FastAI.jl already defines some convenient constructors for learning methods and you can find them with [`findlearningmethods`](#). Here we can pass in either block types as above or the block instances we got from `loaddataset`.

{cell=main}
```julia
findlearningmethods(blocks)
```

Looks like we can use the [`ImageSegmentation`](#) function to create a learning method for our learning task. Every function returned can be called with `blocks` and, optionally, some keyword arguments for customization.

{cell=main}
```julia
method = ImageSegmentation(blocks; size = (64, 64))
```

And that's the basic workflow for getting started with a supervised task.

### Exercises

1. Find all learning method functions with images as inputs.
