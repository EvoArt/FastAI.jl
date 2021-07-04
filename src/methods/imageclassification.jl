

abstract type AbstractImageClassification <: LearningMethod end

"""
    ImageClassification(classes, [sz = (224, 224); kwargs...]) <: LearningMethod

A learning method for single-label image classification:
given an image and a set of `classes`, determine which class the image
falls into. For example, decide if an image contains a dog or a cat.

Images are resized and cropped to `sz` (see [`ProjectiveTransforms`](#))
and preprocessed using [`ImagePreprocessing`](#). `classes` is a vector of the class labels.

## Keyword arguments

- `aug_projection::`[`DataAugmentation.Transform`](#)` = Identity()`: Projective
    augmentation to apply during training. See
    [`ProjectiveTransforms`](#) and [`augs_projection`](#).
- `aug_image::`[`DataAugmentation.Transform`](#)` = Identity()`: Other image
    augmentation to apply to cropped image during training. See
    [`ImagePreprocessing`](#) and [`augs_lighting`](#).
- `means = IMAGENET_MEANS` and `stds = IMAGENET_STDS`: Color channel means and
    standard deviations to use for normalizing the image.
- `buffered = true`: Whether to use inplace transformations when projecting and
  preprocessing image. Reduces memory usage.

## Learning method reference

This learning method implements the following interfaces:

{.tight}
- Core interface
- Plotting interface
- Training interface
- Testing interface

### Types

- **`sample`**: `Tuple`/`NamedTuple` of
    - **`input`**`::AbstractArray{2, T}`: A 2-dimensional array with dimensions (height, width)
        and elements of a color or number type. `Matrix{RGB{Float32}}` is a 2D RGB image,
        while `Array{Float32, 3}` would be a 3D grayscale image. If element type is a number
        it should fall between `0` and `1`. It is recommended to use the `Gray` color type
        to represent grayscale images.
    - **`target`**: A class. Has to be an element in `method.classes`.
- **`x`**`::AbstractArray{Float32, 3}`: a normalized array with dimensions (height, width, color channels). See [`ImagePreprocessing`](#) for additional information.
- **`y`**`::AbstractVector{Float32}`: a one-hot encoded vector of length `length(method.classes)` with true class index  `1.` and all other entries `0`.
- **`y`**`::AbstractVector{Float32}`: vector of predicted class scores.

### Model sizes

Array sizes that compatible models must conform to.

- Full model: `(sz..., 3, batch) -> (length(classes), batch)`
- Backbone model: `(sz..., 3, batch) -> ((sz ./ f)..., ch, batch)` where `f`
    is a downscaling factor `f = 2^k`

It is recommended *not* to use [`Flux.softmax`](#) as the final layer for custom models.
Instead use [`Flux.logitcrossentropy`](#) as the loss function for increased numerical
stability. This is done automatically if using with `methodmodel` and `methodlossfn`.
"""
mutable struct ImageClassification{N} <: AbstractImageClassification
    classes::AbstractVector
    projections::ProjectiveTransforms{N}
    imagepreprocessing::ImagePreprocessing
end

mutable struct ImageClassificationMulti{N} <: AbstractImageClassification
    classes::AbstractVector
    projections::ProjectiveTransforms{N}
    imagepreprocessing::ImagePreprocessing
end

function Base.show(io::IO, method::AbstractImageClassification)
    show(io, ShowTypeOf(method))
    fields = (
        classes = ShowLimit(ShowList(method.classes, brackets="[]"), limit=80),
        projections = method.projections,
        imageprepocessing = method.imagepreprocessing
    )
    show(io, ShowProps(fields, new_lines=true))
end

function ImageClassification(
        classes::AbstractVector,
        sz=(224, 224);
        aug_projection=Identity(),
        aug_image=Identity(),
        means=IMAGENET_MEANS,
        stds=IMAGENET_STDS,
        C=RGB{N0f8},
        T=Float32,
        buffered=true,
    )
    projectivetransforms = ProjectiveTransforms(sz; augmentations=aug_projection, buffered=buffered)
    imagepreprocessing = ImagePreprocessing(;means=means, stds=stds, augmentations=aug_image, C=C, T=T)
    ImageClassification(classes, projectivetransforms, imagepreprocessing)
end


# Core interface implementation

DLPipelines.encode(method::AbstractImageClassification, context, (input, target)) = (
    encodeinput(method, context, input),
    encodetarget(method, context, target),
)

function DLPipelines.encodeinput(
        method::AbstractImageClassification,
        context,
        image)
    imagecropped = run(method.projections, context, image)
    x = run(method.imagepreprocessing, context, imagecropped)
    return x
end


function DLPipelines.encodetarget(
        method::ImageClassification,
        context,
        category)
    idx = findfirst(isequal(category), method.classes)
    isnothing(idx) && error("`category` could not be found in `method.classes`.")
    return DataAugmentation.onehot(idx, length(method.classes))
end


function DLPipelines.encodetarget!(
        y::AbstractVector{T},
        method::ImageClassification,
        context,
        category) where T
    fill!(y, zero(T))
    idx = findfirst(isequal(category), method.classes)
    y[idx] = one(T)
    return y
end

DLPipelines.decodeŷ(method::ImageClassification, context, ŷ) = method.classes[argmax(ŷ)]

# Plotting interface

function plotsample!(f, method::AbstractImageClassification, sample)
    image, class = sample
    f[1, 1] = ax1 = imageaxis(f, title = string(class))
    plotimage!(ax1, image)
end

function plotxy!(f, method::AbstractImageClassification, x, y)
    image = invert(method.imagepreprocessing, x)
    target = decodeŷ(method, Validation(), y)
    i = argmax(y)
    ax1 = f[1, 1] = imageaxis(f, title = "$target", titlesize=12.)
    plotimage!(ax1, image)
end

function plotprediction!(f, method::AbstractImageClassification, x, ŷ, y)
    image = invert(method.imagepreprocessing, x)
    target = decodeŷ(method, Validation(), y)
    target_pred = decodeŷ(method, Validation(), ŷ)
    ax1 = f[1, 1] = imageaxis(f, title = "Pred: $target_pred | GT: $target", titlesize=12.)
    plotimage!(ax1, image)
    return f
end

# Training interface

"""
    methodmodel(method::ImageClassifiction, backbone)

Construct a model for image classification from `backbone` which should
be a convolutional feature extractor like a ResNet (without the
classification head).

The input and output sizes are `(h, w, 3, b)` and `(length(method.classes), b)`.
"""
function DLPipelines.methodmodel(method::AbstractImageClassification, backbone)
    h, w, ch, b = Flux.outdims(backbone, (method.projections.sz..., 3, 1))
    head = Models.visionhead(ch, length(method.classes), p = 0.)
    return Chain(backbone, head)
end

DLPipelines.methodlossfn(::ImageClassification) = Flux.Losses.logitcrossentropy

# Testing interface

DLPipelines.mocksample(method::AbstractImageClassification) = (
    mockinput(method),
    mocktarget(method),
)

function DLPipelines.mockinput(method::ImageClassification)
    inputsz = rand.(UnitRange.(method.projections.sz, method.projections.sz .* 2))
    return rand(RGB{N0f8}, inputsz)
end


function DLPipelines.mocktarget(method::ImageClassification)
    rand(1:length(method.classes))
end


function DLPipelines.mockmodel(method::ImageClassification)
    return xs -> rand(Float32, length(method.classes), size(xs)[end])
end
